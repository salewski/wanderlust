;;; elmo-file.el --- File interface for ELMO.

;; Copyright (C) 2000 Yuuichi Teranishi <teranisi@gohome.org>

;; Author: Yuuichi Teranishi <teranisi@gohome.org>
;; Keywords: mail, net news

;; This file is part of ELMO (Elisp Library for Message Orchestration).

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.
;;

;;; Commentary:
;;

;;; Code:
;;
(require 'elmo)
(require 'elmo-map)
(require 'mime-edit)

(eval-and-compile
  (luna-define-class elmo-file-folder (elmo-map-folder) (file-path))
  (luna-define-internal-accessors 'elmo-file-folder))

(luna-define-method elmo-folder-initialize ((folder
					     elmo-file-folder)
					    name)
  (elmo-file-folder-set-file-path-internal folder name)
  folder)

(luna-define-method elmo-folder-expand-msgdb-path ((folder
						    elmo-file-folder))
  (expand-file-name
   (elmo-replace-string-as-filename (elmo-folder-name-internal folder))
   (expand-file-name "file" elmo-msgdb-directory)))

(defun elmo-file-make-date-string (attrs)
  (let ((s (current-time-string (nth 5 attrs))))
    (string-match "\\`\\([A-Z][a-z][a-z]\\) +[A-Z][a-z][a-z] +[0-9][0-9]? *[0-9][0-9]?:[0-9][0-9]:[0-9][0-9] *[0-9]?[0-9]?[0-9][0-9]"
		  s)
    (concat (elmo-match-string 1 s) ", "
	    (timezone-make-date-arpa-standard s (current-time-zone)))))

(defun elmo-file-msgdb-create-entity (msgdb folder number)
  "Create msgdb entity for the message in the FOLDER with NUMBER."
  (let* ((file (elmo-message-file-name folder number))
	 (attrs (file-attributes file)))
    (and (not (file-directory-p file))
	 attrs
	 (elmo-msgdb-make-message-entity
	  (elmo-msgdb-message-entity-handler msgdb)
	  :message-id (concat "<" (elmo-replace-in-string
				   file "/" ":")
			      "@" (system-name))
	  :number number
	  :size (nth 7 attrs)
	  :date (elmo-file-make-date-string attrs)
	  :subject (file-name-nondirectory file)
	  :from (concat (user-full-name (nth 2 attrs))
			" <" (user-login-name (nth 2 attrs)) "@"
			(system-name) ">")))))

(luna-define-method elmo-folder-msgdb-create ((folder elmo-file-folder)
					      numlist flag-table)
  (let ((new-msgdb (elmo-make-msgdb))
	entity mark i percent num)
    (setq num (length numlist))
    (setq i 0)
    (message "Creating msgdb...")
    (while numlist
      (setq entity
	    (elmo-file-msgdb-create-entity new-msgdb folder (car numlist)))
      (when entity
	(elmo-msgdb-append-entity new-msgdb entity '(new unread)))
      (when (> num elmo-display-progress-threshold)
	(setq i (1+ i))
	(setq percent (/ (* i 100) num))
	(elmo-display-progress
	 'elmo-folder-msgdb-create "Creating msgdb..."
	 percent))
      (setq numlist (cdr numlist)))
    (message "Creating msgdb...done")
    new-msgdb))

(luna-define-method elmo-folder-message-file-p ((folder elmo-file-folder))
  t)

(luna-define-method elmo-message-file-name ((folder elmo-file-folder)
					    number)
  (expand-file-name (car (split-string
			  (elmo-map-message-location folder number)
			  "/"))
		    (elmo-file-folder-file-path-internal folder)))

(luna-define-method elmo-folder-message-make-temp-file-p
  ((folder elmo-file-folder))
  t)

(luna-define-method elmo-folder-diff ((folder elmo-file-folder))
  (cons nil nil))

(luna-define-method elmo-folder-message-make-temp-files ((folder
							  elmo-file-folder)
							 numbers
							 &optional
							 start-number)
  (let ((temp-dir (elmo-folder-make-temporary-directory folder))
	(cur-number (if start-number 0)))
    (dolist (number numbers)
      (elmo-copy-file
       (elmo-message-file-name folder number)
       (expand-file-name
	(int-to-string (if start-number (incf cur-number) number))
	temp-dir)))
    temp-dir))

(luna-define-method elmo-map-message-fetch ((folder elmo-file-folder)
					    location strategy
					    &optional section unseen)
  (let ((file (expand-file-name (car (split-string location "/"))
				(elmo-file-folder-file-path-internal folder)))
	charset guess uid)
    (when (file-exists-p file)
      (set-buffer-multibyte nil)
      (prog1
	  (insert-file-contents-as-binary file)
	(unless (or (std11-field-body "To")
		    (std11-field-body "Cc")
		    (std11-field-body "Subject"))
	  (setq guess (mime-find-file-type file))
	  (when (string= (nth 0 guess) "text")
	    (set-buffer-multibyte t)
	    (decode-coding-region
	     (point-min) (point-max)
	     elmo-mime-display-as-is-coding-system)
	    (setq charset (detect-mime-charset-region (point-min)
						      (point-max))))
	  (goto-char (point-min))
	  (setq uid (nth 2 (file-attributes file)))
	  (insert "From: " (concat (user-full-name uid)
				   " <"(user-login-name uid) "@"
				   (system-name) ">") "\n")
	  (insert "Subject: " (file-name-nondirectory file) "\n")
	  (insert "Date: "
		  (elmo-file-make-date-string (file-attributes file))
		  "\n")
	  (insert "Message-ID: "
		  (concat "<" (elmo-replace-in-string file "/" ":")
			  "@" (system-name) ">\n"))
	  (insert "Content-Type: "
		  (concat (nth 0 guess) "/" (nth 1 guess))
		  (or (and (string= (nth 0 guess) "text")
			   (concat
			    "; charset=" (upcase (symbol-name charset))))
		      "")
		  "\nMIME-Version: 1.0\n\n")
	  (when (string= (nth 0 guess) "text")
	    (encode-mime-charset-region (point-min) (point-max) charset))
	  (set-buffer-multibyte nil))))))

(luna-define-method elmo-map-folder-list-message-locations
  ((folder elmo-file-folder))
  (mapcar
   (lambda (file)
     (concat
      file "/"
      (mapconcat
       'number-to-string
       (nth 5 (file-attributes (expand-file-name
				file
				(elmo-file-folder-file-path-internal
				 folder))))
       ":")))
   (directory-files (elmo-file-folder-file-path-internal folder))))

(luna-define-method elmo-folder-exists-p ((folder elmo-file-folder))
  (file-directory-p (elmo-file-folder-file-path-internal folder)))

(luna-define-method elmo-folder-list-subfolders ((folder elmo-file-folder)
						 &optional one-level)
  (when (file-directory-p (elmo-file-folder-file-path-internal folder))
    (append
     (list (elmo-folder-name-internal folder))
     (delq nil
	   (mapcar
	    (lambda (file)
	      (when (and (file-directory-p
			  (expand-file-name
			   file
			   (elmo-file-folder-file-path-internal folder)))
			 (not (string= file "."))
			 (not (string= file "..")))
		(concat (elmo-folder-name-internal folder) "/" file)))
	    (directory-files (elmo-file-folder-file-path-internal
			      folder)))))))

(require 'product)
(product-provide (provide 'elmo-file) (require 'elmo-version))

;;; elmo-file.el ends here
