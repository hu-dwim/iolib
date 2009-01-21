;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; indent-tabs-mode: nil -*-
;;;
;;; --- File devices.
;;;

(in-package :io.zeta-streams)

;;;-------------------------------------------------------------------------
;;; Classes and Types
;;;-------------------------------------------------------------------------

(defclass file-device (device)
  ((filename :initarg :filename
             :accessor file-device-filename)
   (flags :initarg flags
          :accessor file-device-flags)
   (mode :initarg mode
         :accessor file-device-mode)
   (delete-if-exists :initarg :delete-if-exists
                     :accessor file-device-delete-if-exists-p)))

(defclass memory-mapped-file-device (file-device direct-device) ())

(defvar *default-open-mode* #o666)

(defclass file-zstream (single-channel-zstream) ())


;;;-------------------------------------------------------------------------
;;; Generic functions
;;;-------------------------------------------------------------------------

(defgeneric open-file (filename &key direction if-exists if-does-not-exist
                      truncate append extra-flags mode synchronized
                      buffering buffer-size external-format))


;;;-------------------------------------------------------------------------
;;; Constructors
;;;-------------------------------------------------------------------------

(defmethod shared-initialize :after
    ((device file-device) slot-names &rest initargs
     &key handle filename flags (mode *default-open-mode*) delete-if-exists)
  (declare (ignore slot-names))
  ;; FIXME: use new pathnames
  (check-type filename string)
  (setf (file-device-filename device) (copy-seq filename))
  (with-device (device)
    (device-open device slot-names initargs)))


;;;-------------------------------------------------------------------------
;;; PRINT-OBJECT
;;;-------------------------------------------------------------------------

(defmethod print-object ((file file-device) stream)
  (print-unreadable-object (file stream :identity t :type nil)
    (format stream "File device for ~S" (file-device-filename file))))

(defmethod print-object ((file file-zstream) stream)
  (print-unreadable-object (file stream :identity t :type t)
    (format stream "wrapping ~S" (zstream-device file))))


;;;-------------------------------------------------------------------------
;;; DEVICE-OPEN
;;;-------------------------------------------------------------------------

(defmethod device-open ((device file-device) slot-names initargs)
  (destructuring-bind (&key handle filename flags mode delete-if-exists)
      initargs
    (labels ((handle-error (c)
               (posix-file-error c filename "opening"))
             (try-delete ()
               (handler-case
                   (%sys-unlink filename)
                 (posix-error (c) (handle-error c))))
             (try-open (&optional (retry-on-delete t))
               (handler-case
                   (%sys-open filename flags mode)
                 (eexist (c)
                   (cond ((and retry-on-delete delete-if-exists)
                          (try-delete) (try-open nil))
                         (t (handle-error c))))
                 (posix-error (c)
                   (handle-error c))
                 (:no-error (fd) fd))))
      (let ((fd (or handle (try-open))))
        (%set-fd-nonblock fd)
        (setf (device-handle device) fd))))
  (values device))


;;;-------------------------------------------------------------------------
;;; RELINQUISH
;;;-------------------------------------------------------------------------

(defmethod relinquish ((device file-device) &key abort)
  (declare (ignore abort))
  (%sys-close (device-handle device))
  (setf (device-handle device) nil)
  (values device))


;;;-------------------------------------------------------------------------
;;; DEVICE-POSITION
;;;-------------------------------------------------------------------------

(defmethod device-position ((device file-device))
  (handler-case
      (%sys-lseek (device-handle device) 0 seek-cur)
    (posix-error (err)
      (posix-file-error err device "seeking on"))))

(defmethod (setf device-position)
    (position (device file-device) &optional (from :start))
  (handler-case
      (%sys-lseek (device-handle device) position
                  (ecase from
                    (:start seek-set)
                    (:current seek-cur)
                    (:end seek-end)))
    (posix-error (err)
      (posix-file-error err device "seeking on"))))


;;;-------------------------------------------------------------------------
;;; DEVICE-LENGTH
;;;-------------------------------------------------------------------------

(defmethod device-length ((device file-device))
  (handler-case
      (stat-size (%sys-fstat (device-handle device)))
    (posix-error (err)
      (posix-file-error err device "getting status of"))))

(defmethod (setf device-length) (length (device file-device))
  (handler-case
      (%sys-ftruncate (device-handle device) length)
    (posix-error (err)
      (posix-file-error err device "truncating"))))


;;;-------------------------------------------------------------------------
;;; I/O WAIT
;;;-------------------------------------------------------------------------

(defmethod device-poll ((device file-device) direction &optional timeout)
  (multiple-value-bind (readp rhupp writep whupp)
      (poll-fd (device-handle device) direction timeout)
    (ecase direction
      (:input  (values readp  rhupp))
      (:output (values writep whupp)))))


;;;-------------------------------------------------------------------------
;;; DEVICE-READ
;;;-------------------------------------------------------------------------

(defmethod device-read/non-blocking ((device file-device) vector start end)
  (with-device (device)
    (%read-octets/non-blocking (device-handle device) vector start end)))

(defmethod device-read/timeout ((device file-device) vector
                                start end timeout)
  (with-device (device)
    (%read-octets/timeout (device-handle device) vector start end timeout)))


;;;-------------------------------------------------------------------------
;;; DEVICE-WRITE
;;;-------------------------------------------------------------------------

(defmethod device-write/non-blocking ((device file-device) vector start end)
  (with-device (device)
    (%write-octets/non-blocking (device-handle device) vector start end)))

(defmethod device-write/timeout ((device file-device) vector
                                 start end timeout)
  (with-device (device)
    (%write-octets/timeout (device-handle device) vector start end timeout)))


;;;-------------------------------------------------------------------------
;;; OPEN-FILE
;;;-------------------------------------------------------------------------

(defmethod open-file
    (filename &key (direction :input) (if-exists :default)
     (if-does-not-exist :default) truncate append (extra-flags 0)
     (mode *default-open-mode*) synchronized (buffering :full)
     (buffer-size +default-iobuf-size+) (external-format :default))
  (check-type direction file-direction)
  (check-type extra-flags file-flags)
  (check-type mode file-mode)
  (check-type buffering (or null stream-buffering))
  (when (or (and (null if-exists)
                 (null if-does-not-exist))
            (and (eql :error if-exists)
                 (eql :error if-does-not-exist)))
    (error 'program-error))
  ;; FIXME: check for file type TTY and adjust buffering
  (let ((file-device
         (%open-file filename direction if-exists if-does-not-exist
                     truncate append extra-flags mode)))
    (if (null buffering)
        (values file-device)
        (make-instance 'file-zeta-stream
                       :device file-device
                       :synchronized synchronized
                       :buffering buffering
                       :size buffer-size
                       :external-format external-format))))

(defun %open-file (filename direction if-exists if-does-not-exist
                   truncate append extra-flags mode)
  (let ((flags 0))
    (setf (values flags if-exists if-does-not-exist)
          (process-file-direction direction flags
                                  if-exists if-does-not-exist))
    (setf (values flags if-exists if-does-not-exist)
          (process-file-flags direction flags if-exists if-does-not-exist
                              truncate append extra-flags))
    (handler-case
        (make-instance 'file-device
                       :filename (namestring filename)
                       :flags (logior flags extra-flags)
                       :mode mode
                       :delete-if-exists (eql :delete if-exists))
      (posix-file-error (error)
        (case (posix-file-error-identifier error)
          (:enoent
           (if (null if-does-not-exist) nil (error error)))
          (:eexist
           (if (null if-exists) nil (error error)))
          (t (error error))))
      (:no-error (file) file))))

(defun process-file-direction (direction flags if-exists if-does-not-exist)
  (macrolet ((add-flags (&rest %flags)
               `(setf flags (logior flags ,@%flags))))
    (when (eql :default if-exists) (setf if-exists :overwrite))
    (ecase direction
      (:input
       (add-flags o-rdonly)
       (check-type if-exists (member :overwrite :error-if-symlink))
       (check-type if-does-not-exist (member :default :error))
       (when (eql :default if-does-not-exist)
         (setf if-does-not-exist :error)))
      ((:output :io)
       (add-flags (if (eql :io direction) o-rdwr o-wronly))
       (check-type if-exists file-if-exists)
       (check-type if-does-not-exist file-if-does-not-exist)
       (when (eql :default if-does-not-exist)
         (setf if-does-not-exist :create))))
    (values flags if-exists if-does-not-exist)))

(defun process-file-flags (direction flags if-exists if-does-not-exist
                           truncate append extra-flags)
  (macrolet ((add-flags (&rest %flags)
               `(setf flags (logior flags ,@%flags))))
    (case if-exists
      (:error
       (unless (eql :input direction) (add-flags o-excl)))
      (:delete
       (add-flags o-excl o-creat))
      (:error-if-symlink
       (add-flags o-nofollow)))
    (case if-does-not-exist
      (:create (add-flags o-creat)))
    (cond
      (truncate
       (unless (eql :input direction) (add-flags o-trunc)))
      (append
       (when (eql :output direction) (add-flags o-append)))
      (extra-flags
       (add-flags extra-flags))))
  (values flags if-exists if-does-not-exist))
