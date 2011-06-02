;;; tramp-adb.el --- Functions for calling Android Debug Bridge from Tramp

;; Copyright (C) 2011  Juergen Hoetzel

;; Author: Juergen Hoetzel <juergen@archlinux.org>
;; Keywords: comm, processes

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; In order to activate this package, perform the following steps:
;;
;; - Add a symlink into the Tramp directory
;;   ln -s /path/to/this/tramp-adb.el /path/to/tramp/lisp/tramp-adb.el
;;
;; - Regenerate tramp-loaddefs.el
;;   cd /path/to/tramp; rm lisp/tramp-loaddefs.el; make
;;
;; - Add the following form into your .emacs
;;   (setq tramp-adb-sdk-dir "/path/to/android/sdk")

;;; Code:

(require 'tramp)

(defcustom tramp-adb-sdk-dir "~/Android/sdk"
  "Set to the directory containing the Android SDK."
  :type 'string
  :group 'tramp-adb)

;;;###tramp-autoload
(defconst tramp-adb-method "adb"
  "*When this method name is used, forward all calls to Android Debug Bridge.")

(defconst tramp-adb-prompt "^[#\\$][[:space:]]+"
  "Regexp used as prompt in ADB shell.")

(defconst tramp-adb-ls-date-regexp "[[:space:]][0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9][[:space:]][0-9][0-9]:[0-9][0-9][[:space:]]")

;;;###tramp-autoload
(add-to-list 'tramp-methods `(,tramp-adb-method))

;;;###tramp-autoload
(eval-after-load 'tramp
  '(tramp-set-completion-function
    tramp-adb-method '((tramp-adb-parse-device-names ""))))

;;;###tramp-autoload
(add-to-list 'tramp-foreign-file-name-handler-alist
	     (cons 'tramp-adb-file-name-p 'tramp-adb-file-name-handler))

(defconst tramp-adb-file-name-handler-alist
  '((directory-file-name . tramp-handle-directory-file-name)
    (dired-uncache . tramp-handle-dired-uncache)
    (file-name-as-directory . tramp-handle-file-name-as-directory)
    (file-name-completion . tramp-handle-file-name-completion)
    (file-name-all-completions . tramp-adb-handle-file-name-all-completions)
    (file-attributes . tramp-adb-handle-file-attributes)
    (file-name-directory . tramp-handle-file-name-directory)
    (file-name-nondirectory . tramp-handle-file-name-nondirectory)
    (file-truename . tramp-adb-handle-file-truename)
    (file-newer-than-file-p . tramp-handle-file-newer-than-file-p)
    (file-name-as-directory . tramp-handle-file-name-as-directory)
    (file-regular-p . tramp-handle-file-regular-p)
    (file-remote-p . tramp-handle-file-remote-p)
    (file-directory-p . tramp-adb-handle-file-directory-p)
    (file-symlink-p . tramp-handle-file-symlink-p)
    (file-exists-p . tramp-adb-handle-file-exists-p)
    (file-readable-p . tramp-handle-file-exists-p)
    (file-writable-p . tramp-adb-handle-file-writable-p)
    (file-local-copy . tramp-adb-handle-file-local-copy)
    (file-modes . tramp-handle-file-modes)
    (expand-file-name . tramp-adb-handle-expand-file-name)
    (find-backup-file-name . tramp-handle-find-backup-file-name)
    (directory-files . tramp-adb-handle-directory-files)
    (make-directory . tramp-adb-handle-make-directory)
    (delete-directory . tramp-adb-handle-delete-directory)
    (delete-file . tramp-adb-handle-delete-file)
    (load . tramp-handle-load)
    (insert-directory . tramp-adb-handle-insert-directory)
    (insert-file-contents . tramp-handle-insert-file-contents)
    (substitute-in-file-name . tramp-handle-substitute-in-file-name)
    (unhandled-file-name-directory . tramp-handle-unhandled-file-name-directory)
    (vc-registered . ignore)	;no  vc control files on Android devices
    (write-region . tramp-adb-handle-write-region)
    (set-file-modes . tramp-adb-handle-set-file-modes)
    (set-file-times . ignore)
    (copy-file . tramp-adb-handle-copy-file)
    (rename-file . tramp-adb-handle-rename-file))
  "Alist of handler functions for Tramp ADB method.")

;;;###tramp-autoload
(defun tramp-adb-file-name-p (filename)
  "Check if it's a filename for ADB."
  (let ((v (tramp-dissect-file-name filename)))
    (string= (tramp-file-name-method v) tramp-adb-method)))

;;;###tramp-autoload
(defun tramp-adb-file-name-handler (operation &rest args)
  "Invoke the ADB handler for OPERATION.
First arg specifies the OPERATION, second arg is a list of arguments to
pass to the OPERATION."
  (let ((fn (assoc operation tramp-adb-file-name-handler-alist))
	;; `tramp-default-host's default value is (system-name).  Not
	;; useful for us.
	(tramp-default-host
	 (unless (equal (eval (car (get 'tramp-default-host 'standard-value)))
			tramp-default-host)
	   tramp-default-host)))
    (if fn
	(save-match-data (apply (cdr fn) args))
      (tramp-run-real-handler operation args))))

;; This cannot be a constant, because `tramp-adb-sdk-dir' is customizable.
(defun tramp-adb-program ()
  "The Android Debug Bridge."
  (expand-file-name "platform-tools/adb" tramp-adb-sdk-dir))

;;;###tramp-autoload
(defun tramp-adb-parse-device-names (ignore)
  "Return a list of (nil host) tuples allowed to access."
  (with-temp-buffer
    (when (zerop (call-process (tramp-adb-program) nil t nil "devices"))
      (let (result)
	(goto-char (point-min))
	(while (search-forward-regexp "^\\(\\S-+\\)[[:space:]]+device$" nil t)
	  (add-to-list 'result (list nil (match-string 1))))
	result))))

(defun tramp-adb-handle-expand-file-name (name &optional dir)
  "Like `expand-file-name' for Tramp files."
  ;; If DIR is not given, use DEFAULT-DIRECTORY or "/".
  (setq dir (or dir default-directory "/"))
  ;; Unless NAME is absolute, concat DIR and NAME.
  (unless (file-name-absolute-p name)
    (setq name (concat (file-name-as-directory dir) name)))
  ;; If NAME is not a Tramp file, run the real handler.
  (if (not (tramp-tramp-file-p name))
      (tramp-run-real-handler 'expand-file-name (list name nil))
    ;; Dissect NAME.
    (with-parsed-tramp-file-name name nil
      (unless (tramp-run-real-handler 'file-name-absolute-p (list localname))
	(setq localname (concat "/" localname)))
      ;; Do normal `expand-file-name' (this does "/./" and "/../").
      ;; We bind `directory-sep-char' here for XEmacs on Windows,
      ;; which would otherwise use backslash.  `default-directory' is
      ;; bound, because on Windows there would be problems with UNC
      ;; shares or Cygwin mounts.
      (let ((directory-sep-char ?/)
	    (default-directory (tramp-compat-temporary-file-directory)))
	(tramp-make-tramp-file-name
	 method user host
	 (tramp-drop-volume-letter
	  (tramp-run-real-handler
	   'expand-file-name (list localname))))))))

(defun tramp-adb-handle-file-directory-p (filename)
  "Like `file-directory-p' for Tramp files."
  (let ((symlink (file-symlink-p filename)))
    (if (stringp symlink)
	(file-directory-p symlink)
      (car (file-attributes filename)))))

;; This is derived from `tramp-sh-handle-file-truename'.  Maybe the
;; code could be shared?
(defun tramp-adb-handle-file-truename (filename &optional counter prev-dirs)
  "Like `file-truename' for Tramp files."
  (with-parsed-tramp-file-name (expand-file-name filename) nil
    (with-file-property v localname "file-truename"
      (let ((result nil))			; result steps in reverse order
	(tramp-message v 4 "Finding true name for `%s'" filename)
	(let* ((directory-sep-char ?/)
	       (steps (tramp-compat-split-string localname "/"))
	       (localnamedir (tramp-run-real-handler
			      'file-name-as-directory (list localname)))
	       (is-dir (string= localname localnamedir))
	       (thisstep nil)
	       (numchase 0)
	       ;; Don't make the following value larger than
	       ;; necessary.  People expect an error message in a
	       ;; timely fashion when something is wrong; otherwise
	       ;; they might think that Emacs is hung.  Of course,
	       ;; correctness has to come first.
	       (numchase-limit 20)
	       symlink-target)
	  (while (and steps (< numchase numchase-limit))
	    (setq thisstep (pop steps))
	    (tramp-message
	     v 5 "Check %s"
	     (mapconcat 'identity
			(append '("") (reverse result) (list thisstep))
			"/"))
	    (setq symlink-target
		  (nth 0 (file-attributes
			  (tramp-make-tramp-file-name
			   method user host
			   (mapconcat 'identity
				      (append '("")
					      (reverse result)
					      (list thisstep))
				      "/")))))
	    (cond ((string= "." thisstep)
		   (tramp-message v 5 "Ignoring step `.'"))
		  ((string= ".." thisstep)
		   (tramp-message v 5 "Processing step `..'")
		   (pop result))
		  ((stringp symlink-target)
		   ;; It's a symlink, follow it.
		   (tramp-message v 5 "Follow symlink to %s" symlink-target)
		   (setq numchase (1+ numchase))
		   (when (file-name-absolute-p symlink-target)
		     (setq result nil))
		   ;; If the symlink was absolute, we'll get a string
		   ;; like "/user@host:/some/target"; extract the
		   ;; "/some/target" part from it.
		   (when (tramp-tramp-file-p symlink-target)
		     (unless (tramp-equal-remote filename symlink-target)
		       (tramp-error
			v 'file-error
			"Symlink target `%s' on wrong host" symlink-target))
		     (setq symlink-target localname))
		   (setq steps
			 (append (tramp-compat-split-string
				  symlink-target "/")
				 steps)))
		  (t
		   ;; It's a file.
		   (setq result (cons thisstep result)))))
	  (when (>= numchase numchase-limit)
	    (tramp-error
	     v 'file-error
	     "Maximum number (%d) of symlinks exceeded" numchase-limit))
	  (setq result (reverse result))
	  ;; Combine list to form string.
	  (setq result
		(if result
		    (mapconcat 'identity (cons "" result) "/")
		  "/"))
	  (when (and is-dir (or (string= "" result)
				(not (string= (substring result -1) "/"))))
	    (setq result (concat result "/"))))

        (tramp-message v 4 "True name of `%s' is `%s'" filename result)
        (tramp-make-tramp-file-name method user host result)))))

(defun tramp-adb-handle-file-attributes (filename &optional id-format)
  "Like `file-attributes' for Tramp files."
  (unless id-format (setq id-format 'integer))
  (ignore-errors
    (with-parsed-tramp-file-name filename nil
      (with-file-property v localname (format "file-attributes-%s" id-format)
	(tramp-adb-barf-unless-okay
	 v (format "ls -d -l %s" (tramp-shell-quote-argument localname)) "")
	(with-current-buffer (tramp-get-buffer v)
	  (tramp-adb-sh-fix-ls-output)
	  (let* ((columns (split-string (buffer-string)))
		 (mod-string (nth 0 columns))
		 (is-dir (eq ?d (aref mod-string 0)))
		 (is-symlink (eq ?l (aref mod-string 0)))
		 (symlink-target (and is-symlink (cadr (split-string (buffer-string) "\\( -> \\|\n\\)"))))
		 (uid (nth 1 columns))
		 (gid (nth 2 columns))
		 (date (format "%s %s" (nth 4 columns) (nth 5 columns)))
		 (size (string-to-int (nth 3 columns))))
	    (list
	     (or is-dir symlink-target)
	     1 					;link-count
	     ;; no way to handle numeric ids in Androids ash
	     (if (eq id-format 'integer) 0 uid)
	     (if (eq id-format 'integer) 0 gid)
	     '(0 0) ; atime
	     (date-to-time date) ; mtime
	     '(0 0) ; ctime
	     size
	     mod-string
	     ;; fake
	     t 1 1)))))))

(defun tramp-adb--gnu-switches-to-ash
  (switches)
  "Almquist shell can't handle multiple arguments.
Convert (\"-al\") to (\"-a\" \"-l\").  Remove arguments like \"--dired\"."
  (split-string
   (apply 'concat
	  (mapcar (lambda (s)
		    (replace-regexp-in-string
		     "\\(.\\)"  " -\\1"
		     (replace-regexp-in-string "^-" "" s)))
		  ;; FIXME: Warning about removed switches (long and non-dash).
		  (remove-if
		   (lambda (s) (string-match "\\(^--\\|^[^-]\\)" s))
		   switches)))))

(defun tramp-adb-handle-insert-directory
  (filename switches &optional wildcard full-directory-p)
  "Like `insert-directory' for Tramp files."
  (when (stringp switches)
    (setq switches (tramp-adb--gnu-switches-to-ash (split-string switches))))
  (with-parsed-tramp-file-name (expand-file-name filename) nil
    (with-current-buffer (tramp-get-buffer v)
      (let ((name (tramp-shell-quote-argument (directory-file-name localname)))
	    (switch-d (member "-d" switches))
	    (switch-t (member "-t" switches))
	    (switches (mapconcat 'identity (remove "-t" switches) " ")))
	(tramp-adb-barf-unless-okay
	 v (format "ls %s %s" switches name)
	 "Cannot insert directory listing: %s" filename)
	(unless switch-d
	  ;; We insert also filename/. and filename/.., because "ls" doesn't.
	  (narrow-to-region (point) (point))
	  (ignore-errors
	    (tramp-adb-barf-unless-okay
	     v (format "ls -d %s %s %s"
		       switches
		       (concat (file-name-as-directory name) ".")
		       (concat (file-name-as-directory name) ".."))
	     "Cannot insert directory listing: %s" filename))
	  (widen))
	(tramp-adb-sh-fix-ls-output switch-t)))
    (insert-buffer-substring (tramp-get-buffer v))))

(defun tramp-adb-sh-fix-ls-output (&optional sort-by-time)
  "Androids ls command doesn't insert size column for directories: Emacs dired can't find files. Insert dummy 0 in empty size columns."
  (save-excursion
    ;; Insert missing size.
    (goto-char (point-min))
    (while (search-forward-regexp "[[:space:]]\\([[:space:]][0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9][[:space:]]\\)" nil t)
      (replace-match "0\\1" "\\1" nil)
      ;; Insert missing "/".
      (when (looking-at "[0-9][0-9]:[0-9][0-9][[:space:]]+$")
	(end-of-line)
	(insert "/")))
    ;; Sort entries.
    (let* ((lines (split-string (buffer-string) "\n" t))
	   (sorted-lines
	    (sort
	     lines
	     (if sort-by-time
		 'tramp-adb-ls-output-time-less-p
	       'tramp-adb-ls-output-name-less-p))))
      (delete-region (point-min) (point-max))
      (insert "  " (mapconcat 'identity sorted-lines "\n  ")))
    ;; Add final newline.
    (goto-char (point-max))
    (unless (= (point) (line-beginning-position))
      (insert "\n"))))


(defun tramp-adb-ls-output-time-less-p (a b)
  "Sort \"ls\" output by time, descending."
  (let (time-a time-b)
    (string-match tramp-adb-ls-date-regexp a)
    (setq time-a (apply 'encode-time (parse-time-string (match-string 0 a))))
    (string-match tramp-adb-ls-date-regexp b)
    (setq time-b (apply 'encode-time (parse-time-string (match-string 0 b))))
    (time-less-p time-b time-a)))

(defun tramp-adb-ls-output-name-less-p (a b)
  "Sort \"ls\" output by name, ascending."
  (let (posa posb)
    (string-match dired-move-to-filename-regexp a)
    (setq posa (match-end 0))
    (string-match dired-move-to-filename-regexp b)
    (setq posb (match-end 0))
    (string-lessp (substring a posa) (substring b posb))))

(defun tramp-adb-handle-directory-files (dir &optional full match nosort files-only)
  "Like `directory-files' for Tramp files."
  (with-parsed-tramp-file-name dir nil
    (tramp-adb-send-command
     v (format "ls %s" (tramp-shell-quote-argument localname)))
    (with-current-buffer (tramp-get-buffer v)
      (remove-if (lambda (l) (string-match  "^[[:space:]]*$" l))
		 (split-string (buffer-string) "\n")))))

(defun tramp-adb-handle-make-directory (dir &optional parents)
  "Like `make-directory' for Tramp files."
  (setq dir (expand-file-name dir))
  (with-parsed-tramp-file-name dir nil
    (when parents
      (tramp-message
       v 5 "mkdir doesn't handle \"-p\" switch: mkdir \"%s\"" localname))
    (tramp-adb-barf-unless-okay
     v (format "mkdir %s" (tramp-shell-quote-argument localname))
     "Couldn't make directory %s" dir)
    (tramp-flush-directory-property v (file-name-directory localname))))

(defun tramp-adb-handle-delete-directory (directory &optional recursive)
  "Like `delete-directory' for Tramp files."
  (setq directory (expand-file-name directory))
  (with-parsed-tramp-file-name directory nil
    (tramp-flush-file-property v (file-name-directory localname))
    (tramp-flush-directory-property v localname)
    (tramp-adb-barf-unless-okay
     v (format "%s %s"
	       (if recursive "rm -r" "rmdir")
	       (tramp-shell-quote-argument localname))
     "Couldn't delete %s" directory)))

(defun tramp-adb-handle-delete-file (filename &optional trash)
  "Like `delete-file' for Tramp files."
  (setq filename (expand-file-name filename))
  (with-parsed-tramp-file-name filename nil
    (tramp-flush-file-property v (file-name-directory localname))
    (tramp-flush-file-property v localname)
    (tramp-adb-barf-unless-okay
     v (format "rm %s" (tramp-shell-quote-argument localname))
     "Couldn't delete %s" filename)))

(defun tramp-adb-handle-file-name-all-completions (filename directory)
  "Like `file-name-all-completions' for Tramp files."
  (all-completions
   filename
   (with-parsed-tramp-file-name directory nil
     (with-file-property v localname "file-name-all-completions"
       (save-match-data
	 (mapcar
	  (lambda (f)
	    (if (file-directory-p f)
		(file-name-as-directory f)
	      f))
	  (directory-files directory)))))))

(defun tramp-adb-handle-file-local-copy (filename)
  "Like `file-local-copy' for Tramp files."
  (with-parsed-tramp-file-name filename nil
    (unless (file-exists-p filename)
      (tramp-error
       v 'file-error
       "Cannot make local copy of non-existing file `%s'" filename))
    (let ((tmpfile (tramp-compat-make-temp-file filename)))
      (with-progress-reporter
	  v 3 (format "Fetching %s to tmp file %s" filename tmpfile)
	(when (tramp-adb-execute-adb-command v "pull" localname tmpfile)
	  (delete-file tmpfile)
	  (tramp-error
	   v 'file-error "Cannot make local copy of file `%s'" filename))
	(set-file-modes tmpfile (file-modes filename)))
      tmpfile)))

(defun tramp-adb-handle-file-writable-p (filename)
  (with-parsed-tramp-file-name filename nil
    ;; missing "test" command on Android devices
    (tramp-message v 5 "not implemented yet (Assuming /data/data is writable) :%s" localname)
    (let ((rw-path "/data/data"))
      (and (>= (length localname) (length rw-path))
	   (string= (substring localname 0 (length rw-path))
		    rw-path)))))

(defun tramp-adb-handle-write-region
  (start end filename &optional append visit lockname confirm)
  "Like `write-region' for Tramp files."
  (setq filename (expand-file-name filename))
  (with-parsed-tramp-file-name filename nil
    (when append
      (tramp-error
       v 'file-error "Cannot append to file using Tramp (`%s')" filename))
    (when (and confirm (file-exists-p filename))
      (unless (y-or-n-p (format "File %s exists; overwrite anyway? "
				filename))
	(tramp-error v 'file-error "File not overwritten")))
    ;; We must also flush the cache of the directory, because
    ;; `file-attributes' reads the values from there.
    (tramp-flush-file-property v (file-name-directory localname))
    (tramp-flush-file-property v localname)
    (let* ((curbuf (current-buffer))
	   (tmpfile (tramp-compat-make-temp-file filename)))
      (tramp-run-real-handler
       'write-region
       (list start end tmpfile append 'no-message lockname confirm))
      (with-progress-reporter
	  v 3 (format "Moving tmp file %s to %s" tmpfile filename)
	(unwind-protect
	    (when (tramp-adb-execute-adb-command v "push" tmpfile localname)
	      (tramp-error v 'file-error "Cannot write: `%s' filename"))
	  (delete-file tmpfile)))

      (unless (equal curbuf (current-buffer))
	(tramp-error
	 v 'file-error
	 "Buffer has changed from `%s' to `%s'" curbuf (current-buffer))))))

(defun tramp-adb-handle-set-file-modes (filename mode)
  "Like `set-file-modes' for Tramp files."
  (with-parsed-tramp-file-name filename nil
    (tramp-flush-file-property v localname)
    (tramp-adb-barf-unless-okay
     v (format "chmod %s %s" (tramp-compat-decimal-to-octal mode) localname)
     "Error while changing file's mode %s" filename)))

(defun tramp-adb-handle-copy-file
  (filename newname &optional ok-if-already-exists keep-date
	    preserve-uid-gid preserve-selinux-context)
  "Like `copy-file' for Tramp files.
PRESERVE-UID-GID and PRESERVE-SELINUX-CONTEXT are completely ignored."
  (setq filename (expand-file-name filename)
	newname (expand-file-name newname))

  (if (file-directory-p filename)
      (copy-directory filename newname keep-date)
    (with-progress-reporter
	(tramp-dissect-file-name (if (file-remote-p filename) filename newname))
	0 (format "Copying %s to %s" filename newname)

      (let ((tmpfile (file-local-copy filename)))

	(if tmpfile
	    ;; Remote filename.
	    (condition-case err
		(rename-file tmpfile newname ok-if-already-exists)
	      ((error quit)
	       (delete-file tmpfile)
	       (signal (car err) (cdr err))))

	  ;; Remote newname.
	  (when (file-directory-p newname)
	    (setq newname
		  (expand-file-name (file-name-nondirectory filename) newname)))

	  (with-parsed-tramp-file-name newname nil
	    (when (and (not ok-if-already-exists)
		       (file-exists-p newname))
	      (tramp-error v 'file-already-exists newname))

	    ;; We must also flush the cache of the directory, because
	    ;; `file-attributes' reads the values from there.
	    (tramp-flush-file-property v (file-name-directory localname))
	    (tramp-flush-file-property v localname)
	    (when (tramp-adb-execute-adb-command v "push" filename localname)
	      (tramp-error
	       v 'file-error "Cannot copy `%s' `%s'" filename newname))))))

    ;; KEEP-DATE handling.
    (when keep-date
      (set-file-times newname (nth 5 (file-attributes filename))))))

(defun tramp-adb-handle-rename-file
  (filename newname &optional ok-if-already-exists)
  "Like `rename-file' for Tramp files."
  (setq filename (expand-file-name filename)
	newname (expand-file-name newname))

  (with-parsed-tramp-file-name
      (if (file-remote-p filename) filename newname) nil
    (with-progress-reporter v 0 (format "Renaming %s to %s" newname filename)

      (if (and (tramp-equal-remote filename newname)
	       (not (file-directory-p filename)))
	  (progn
	    (when (and (not ok-if-already-exists)
		       (file-exists-p newname))
	      (tramp-error v 'file-already-exists newname))
	    ;; We must also flush the cache of the directory, because
	    ;; `file-attributes' reads the values from there.
	    (tramp-flush-file-property v (file-name-directory localname))
	    (tramp-flush-file-property v localname)
	    ;; Short track.
	    (tramp-adb-barf-unless-okay
	     v (format "mv %s %s" (file-remote-p filename 'localname) localname)
	     "Error renaming %s to %s" filename newname))

	;; Rename by copy.
	(copy-file filename newname ok-if-already-exists t t)
	(delete-file filename)))))

;; Android doesn't provide test command

(defun tramp-adb-handle-file-exists-p (filename)
  "Like `file-exists-p' for Tramp files."
  (with-parsed-tramp-file-name filename nil
    (with-file-property v localname "file-exists-p"
      (file-attributes filename))))

;; Helper functions

(defun tramp-adb-execute-adb-command (vec &rest args)
  "Returns nil on success error-output on failure."
  (when (tramp-file-name-host vec)
    (setq args (append (list "-s" (tramp-file-name-host vec)) args)))
  (with-temp-buffer
    (prog1
	(unless (zerop (apply 'call-process (tramp-adb-program) nil t nil args))
	  (buffer-string))
      (tramp-message
       vec 6 "%s %s\n%s"
       (tramp-adb-program) (mapconcat 'identity args " ") (buffer-string)))))

;; Connection functions

(defun tramp-adb-send-command (vec command)
  "Send the COMMAND to connection VEC."
  (tramp-adb-maybe-open-connection vec)
  (tramp-message vec 6 "%s" command)
  (tramp-send-string vec command)
  ;; fixme: Race condition
  (tramp-adb-wait-for-output (tramp-get-connection-process vec))
  (with-current-buffer (tramp-get-connection-buffer vec)
    (save-excursion
      (goto-char (point-min))
      ;; We can't use stty to disable echo of command.
      (delete-matching-lines (regexp-quote command))
      ;; When the local machine is W32, there are still trailing ^M.
      ;; There must be a better solution by setting the correct coding
      ;; system, but this requires changes in core Tramp.
      (goto-char (point-min))
      (while (re-search-forward "\r+$" nil t)
	(replace-match "" nil nil)))))

(defun tramp-adb-barf-unless-okay (vec command fmt &rest args)
  "Run COMMAND, check exit status, throw error if exit status not okay.
FMT and ARGS are passed to `error'."
  (tramp-adb-send-command vec (format "%s; echo tramp_exit_status $?" command))
  (with-current-buffer (tramp-get-connection-buffer vec)
    (goto-char (point-max))
    (unless (re-search-backward "tramp_exit_status [0-9]+" nil t)
      (tramp-error
       vec 'file-error "Couldn't find exit status of `%s'" command))
    (skip-chars-forward "^ ")
    (unless (zerop (read (current-buffer)))
      (apply 'tramp-error vec 'file-error fmt args))
    (let (buffer-read-only)
      (delete-region (match-beginning 0) (point-max)))))

(defun tramp-adb-wait-for-output (proc &optional timeout)
  "Wait for output from remote command."
  (unless (buffer-live-p (process-buffer proc))
    (delete-process proc)
    (tramp-error proc 'file-error "Process `%s' not available, try again" proc))
  (with-current-buffer (process-buffer proc)
    (if (tramp-wait-for-regexp proc timeout tramp-adb-prompt)
	(let (buffer-read-only)
	  (goto-char (point-min))
	  (when (search-forward tramp-adb-prompt (point-at-eol) t)
	    (forward-line 1)
	    (delete-region (point-min) (point)))
	  ;; Delete the prompt.
	  (goto-char (point-max))
	  (search-backward tramp-adb-prompt nil t)
	  (delete-region (point) (point-max)))
      (if timeout
	  (tramp-error
	   proc 'file-error
	   "[[Remote adb prompt `%s' not found in %d secs]]"
	   tramp-adb-prompt timeout)
	(tramp-error
	 proc 'file-error
	 "[[Remote prompt `%s' not found]]" tramp-adb-prompt)))))

(defun tramp-adb-maybe-open-connection (vec)
  "Maybe open a connection VEC.
Does not do anything if a connection is already open, but re-opens the
connection if a previous connection has died for some reason."
  (let* ((buf (tramp-get-buffer vec))
	 (p (get-buffer-process buf)))
    (unless
	(and p (processp p) (memq (process-status p) '(run open)))
      (save-match-data
	(when (and p (processp p)) (delete-process p))
	(with-progress-reporter vec 3 "Opening adb shell connection"
	  (let* ((coding-system-for-read 'utf-8-dos) ;is this correct?
		 (process-connection-type tramp-process-connection-type)
		 (args (if (tramp-file-name-host vec)
			   (list "-s" (tramp-file-name-host vec) "shell")
			 (list "shell")))
		 (p (let ((default-directory
			    (tramp-compat-temporary-file-directory)))
		      (apply 'start-process (tramp-buffer-name vec) buf
			     (tramp-adb-program) args))))
	    (tramp-message
	     vec 6 "%s" (mapconcat 'identity (process-command p) " "))
	    ;; Wait for initial prompt.
	    (tramp-adb-wait-for-output p)
	    (unless (eq 'run (process-status p))
	      (tramp-error  vec 'file-error "Terminated!"))
	    (set-process-query-on-exit-flag p nil)))))))

(provide 'tramp-adb)
;;; tramp-adb.el ends here
