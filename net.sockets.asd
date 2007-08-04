;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Indent-tabs-mode: NIL -*-
;;;
;;; bsd-sockets.asd --- ASDF system definition.
;;;
;;; Copyright (C) 2006-2007, Stelian Ionescu  <sionescu@common-lisp.net>
;;;
;;; This code is free software; you can redistribute it and/or
;;; modify it under the terms of the version 2.1 of
;;; the GNU Lesser General Public License as published by
;;; the Free Software Foundation, as clarified by the
;;; preamble found here:
;;;     http://opensource.franz.com/preamble.html
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU Lesser General
;;; Public License along with this library; if not, write to the
;;; Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
;;; Boston, MA 02110-1301, USA

(in-package :common-lisp-user)

(eval-when (:load-toplevel :execute)
  (asdf:oos 'asdf:load-op :cffi-grovel))

(defpackage #:net.sockets-system
  (:use #:common-lisp :cffi-grovel))

(in-package #:net.sockets-system)

(asdf:defsystem :net.sockets
  :description "Socket library."
  :author "Stelian Ionescu <sionescu@common-lisp.net>"
  :maintainer "Stelian Ionescu <sionescu@common-lisp.net>"
  :licence "LLGPL-2.1"
  :depends-on (:cl-posix
               :babel
               :io.streams
               :alexandria
               :split-sequence)
  :pathname (merge-pathnames (make-pathname :directory '(:relative "sockets"))
                             *load-truename*)
  :serial t
  :components
  ((:file "pkgdcl")
   (:file "common")
   (:grovel-file "grovel")
   (:file "conditions")
   (:file "bsd")
   #+windows (:file "winsock")
   (:file "config")
   #-windows (:file "iface")
   (:file "address")
   (:file "address-predicates")
   (:file "resolv")
   (:file "base-sockets")
   (:file "socket-options")
   (:file "socket-methods")
   (:file "make-socket")))
