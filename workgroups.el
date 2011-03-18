;;; workgroups.el --- Workgroups For Windows (for Emacs)
;;
;; Workgroups is an Emacs session manager providing window-configuration
;; switching, persistence, undo/redo, killing/yanking, animated morphing,
;; per-workgroup buffer-lists, and more.

;; Copyright (C) 2010 tlh <thunkout@gmail.com>

;; File:     workgroups.el
;; Author:   tlh <thunkout@gmail.com>
;; Created:  2010-07-22
;; Version   0.2.0
;; Keywords: session management window-configuration persistence

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be
;; useful, but WITHOUT ANY WARRANTY; without even the implied
;; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
;; PURPOSE.  See the GNU General Public License for more details.

;; You should have received a copy of the GNU General Public
;; License along with this program; if not, write to the Free
;; Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
;; MA 02111-1307 USA

;;; Commentary:
;;
;; See the file README.md in `workgroups.el's directory
;;
;;; Installation:
;;
;;; Usage:
;;

;;; Symbol naming conventions:
;;
;; W always refers to a Workgroups window or window tree.
;; WT always refers to a Workgroups window tree.
;; SW always refers to a sub-window or sub-window-tree of a wtree.
;; WL always refers to the window list of a wtree.
;; LN, TN, RN and BN always refer to the LEFT, TOP, RIGHT and BOTTOM
;;   edges of an edge list, where N is a differentiating integer.
;; LS, HS, LB and HB always refer to the LOW-SIDE, HIGH-SIDE, LOW-BOUND
;;   and HIGH-BOUND of a bounds list.  See `wg-with-bounds'.
;; WGBUF always refers to a workgroups buffer object.
;; EBUF always refers to an Emacs buffer object.
;;

;;; Code:

(require 'cl)

(eval-when-compile
  ;; This prevents "assignment to free variable"
  ;; and "function not known to exist" warnings.
  (require 'ido nil t)
  (require 'iswitchb nil t))


;;; consts

(defconst wg-version "0.2.1"
  "Current version of workgroups.")

(defconst wg-persisted-workgroups-tag '-*-workgroups-*-
  "Tag appearing at the beginning of any list of persisted workgroups.")

(defconst wg-persisted-workgroups-format-version "2.0"
  "Current version number of the format of persisted workgroup lists.")


;;; customization

(defgroup workgroups nil
  "Workgroup for Windows -- Emacs session manager"
  :group 'convenience
  :version wg-version)

(defcustom workgroups-mode-hook nil
  "Hook run when workgroups-mode is turned on."
  :type 'hook
  :group 'workgroups)

;; FIXME: This complicates loading and byte-comp too much
(defcustom wg-prefix-key (kbd "C-z")
  "Workgroups' prefix key."
  :type 'string
  :group 'workgroups
  :set (lambda (sym val)
         (custom-set-default sym val)
         (when (and (boundp 'workgroups-mode) workgroups-mode)
           (wg-set-prefix-key))
         val))

(defcustom wg-switch-hook nil
  "Hook run by `wg-switch-to-workgroup'."
  :type 'hook
  :group 'workgroups)

(defcustom wg-no-confirm nil
  "Non-nil means don't request confirmation before various
destructive operations, like `wg-reset'.  This doesn't modify
query-for-save behavior.  Use
`wg-query-for-save-on-workgroups-mode-exit' and
`wg-query-for-save-on-emacs-exit' for that."
  :type 'boolean
  :group 'workgroups)

(defcustom wg-mode-line-on t
  "Toggles Workgroups' mode-line display."
  :type 'boolean
  :group 'workgroups
  :set (lambda (sym val)
         (custom-set-default sym val)
         (force-mode-line-update)))

(defcustom wg-kill-ring-size 20
  "Maximum length of the `wg-kill-ring'."
  :type 'integer
  :group 'workgroups)

(defcustom wg-warning-timeout 1.0
  "Seconds to `sit-for' after a warning message."
  :type 'float
  :group 'workgroups)


;; save and load customization

(defcustom wg-switch-on-load t
  "Non-nil means switch to the first workgroup in a file when it's loaded."
  :type 'boolean
  :group 'workgroups)

(defcustom wg-query-for-save-on-emacs-exit t
  "Non-nil means query to save changes before exiting Emacs.
Exiting workgroups removes its `kill-emacs-query-functions' hook,
so if you set this to nil, you may want to set
`wg-query-for-save-on-workgroups-exit' to t."
  :type 'boolean
  :group 'workgroups)

(defcustom wg-query-for-save-on-workgroups-mode-exit t
  "Non-nil means query to save changes before exiting `workgroups-mode'.
Exiting workgroups removes its `kill-emacs-query-functions' hook,
which is why this variable exists."
  :type 'boolean
  :group 'workgroups)


;; workgroup restoration customization

(defcustom wg-default-buffer "*scratch*"
  "Buffer switched to when a blank workgroup is created.
Also used when a window's buffer can't be restored."
  :type 'string
  :group 'workgroups)

(defcustom wg-restore-position nil
  "Non-nil means restore frame position on workgroup restore."
  :type 'boolean
  :group 'workgroups)

(defcustom wg-restore-scroll-bars t
  "Non-nil means restore scroll-bar settings on workgroup restore."
  :type 'boolean
  :group 'workgroups)

(defcustom wg-restore-fringes t
  "Non-nil means restore fringe settings on workgroup restore."
  :type 'boolean
  :group 'workgroups)

(defcustom wg-restore-margins t
  "Non-nil means restore margin settings on workgroup restore."
  :type 'boolean
  :group 'workgroups)

(defcustom wg-restore-mbs-window t
  "Non-nil means restore `minibuffer-scroll-window' on workgroup restore."
  :type 'boolean
  :group 'workgroups)

(defcustom wg-restore-point t
  "Non-nil means restore `point' on workgroup restore.
This is included mainly so point restoration can be suspended
during `wg-morph' -- you probably want this on."
  :type 'boolean
  :group 'workgroups)

(defcustom wg-restore-point-max t
  "Controls point restoration when point is at `point-max'.
If `point' is at `point-max' when a wconfig is created, put
`point' back at `point-max' when the wconfig is restored, even if
`point-max' has increased in the meantime.  This is useful
in (say) irc buffers where `point-max' is constantly increasing."
  :type 'boolean
  :group 'workgroups)


;; undo/redo customization

(defcustom wg-wconfig-undo-list-max 30
  "Number of past window configs for undo to retain.
A value of nil means no limit."
  :type 'integer
  :group 'workgroups)

;; FIXME: Either convert this to a hash table, or get rid of it
(defcustom wg-commands-that-alter-window-configs
  '(split-window
    split-window-horizontally
    split-window-vertically
    delete-window
    delete-other-windows
    delete-other-windows-vertically
    enlarge-window
    enlarge-window-horizontally
    shrink-window
    shrink-window-horizontally
    shrink-window-if-larger-than-buffer
    switch-to-buffer
    switch-to-buffer-other-window
    switch-to-buffer-other-frame
    ido-switch-buffer
    ido-switch-buffer-other-window
    ido-switch-buffer-other-frame
    iswitchb-buffer
    iswitchb-buffer-other-window
    iswitchb-buffer-other-frame
    balance-windows
    balance-windows-area
    help-with-tutorial
    jump-to-register)
  "List of commands before which to save up-to-date undo info
about the current window-config.  Since Emacs has no
`pre-window-configuration-change-hook', there's no way to save
undo information directly prior to *every* command that modifies
the window-config.  Instead, workgroups saves undo information
prior to every command in this list.  Undo info will still be
mostly correct without including commands in this list, as undo
info is saved *after* every command that alters the window
config (via `window-configuration-change-hook'), but details like
point, mark and `selected-window' will be lost.

Add commands to this list before which you'd like up-to-date undo
info saved."
  :type 'list
  :group 'workgroups)


;; per-workgroup buffer-list customization

(defcustom wg-switch-buffer-filter-order '(unfiltered filtered fallback)
  "Workgroups can filter `ido-switch-buffer's and
`iswitchb-buffer's completions to only the names of those live
buffers that are members of the current workgroup.

The value of this variable determines the completions presented
by the initial call to `wg-switch-to-buffer' (remapped from
`switch-to-buffer'), and those presented after subsequently
hitting \"C-b\".

FIXME: This is all wrong now

Allowable values:
  unfiltered-filtered-fallback:
    Fallback from unfiltered to filtered to switch-to-buffer
  filtered-unfiltered-fallback:
    Fallback from filtered to unfiltered to switch-to-buffer
  unfiltered-filtered-cyclic:
    Toggle between unfiltered and filtered, starting with unfiltered.
  filtered-unfiltered-cyclic:
    Toggle between filtered and unfiltered, starting with filtered.
  Anything else:
    Feature is completely disabled."
  :type 'symbol
  :group 'workgroups)

(defcustom wg-message-on-filter-errors t
  "Non-nil means catch all filter errors and `message' them,
rather than leaving them uncaught."
  :type 'boolean
  :group 'workgroups)


;; morph customization

(defcustom wg-morph-on t
  "Non-nil means use `wg-morph' when restoring wconfigs."
  :type 'boolean
  :group 'workgroups)

(defcustom wg-morph-hsteps 9
  "Columns/iteration to step window edges during `wg-morph'.
Values lower than 1 are invalid."
  :type 'integer
  :group 'workgroups)

(defcustom wg-morph-vsteps 3
  "Rows/iteration to step window edges during `wg-morph'.
Values lower than 1 are invalid."
  :type 'integer
  :group 'workgroups)

(defcustom wg-morph-terminal-hsteps 3
  "Used instead of `wg-morph-hsteps' in terminal frames.
If nil, `wg-morph-hsteps' is used."
  :type 'integer
  :group 'workgroups)

(defcustom wg-morph-terminal-vsteps 1
  "Used instead of `wg-morph-vsteps' in terminal frames.
If nil, `wg-morph-vsteps' is used."
  :type 'integer
  :group 'workgroups)

(defcustom wg-morph-sit-for-seconds 0
  "Seconds to `sit-for' between `wg-morph' iterations.
Should probably be zero unless `redisplay' is *really* fast on
your machine, and `wg-morph-hsteps' and `wg-morph-vsteps' are
already set as low as possible."
  :type 'float
  :group 'workgroups)

(defcustom wg-morph-truncate-partial-width-windows t
  "Bound to `truncate-partial-width-windows' during `wg-morph'.
Non-nil, this prevents weird-looking continuation line behavior,
and can speed up morphing a little.  Lines jump back to their
wrapped status when `wg-morph' is complete."
  :type 'boolean
  :group 'workgroups)


;; display customization

(defcustom wg-use-faces t
  "Nil means don't use faces in various displays."
  :type 'boolean
  :group 'workgroups)

(defcustom wg-mode-line-left-brace "("
  "String to the left of the mode-line display."
  :type 'string
  :group 'workgroups)

(defcustom wg-mode-line-right-brace ")"
  "String to the right of the mode-line display."
  :type 'string
  :group 'workgroups)

(defcustom wg-mode-line-divider ":"
  "String between workgroup position and name in the mode-line display."
  :type 'string
  :group 'workgroups)

(defcustom wg-display-left-brace "( "
  "String to the left of the list display."
  :type 'string
  :group 'workgroups)

(defcustom wg-display-right-brace " )"
  "String to the right of the list display."
  :type 'string
  :group 'workgroups)

(defcustom wg-display-divider " | "
  "String between workgroup names in the list display."
  :type 'string
  :group 'workgroups)

(defcustom wg-display-current-workgroup-left-decor "-<{ "
  "String to the left of the current workgroup name in the list display."
  :type 'string
  :group 'workgroups)

(defcustom wg-display-current-workgroup-right-decor " }>-"
  "String to the right of the current workgroup name in the list display."
  :type 'string
  :group 'workgroups)

(defcustom wg-display-previous-workgroup-left-decor "*"
  "String to the left of the previous workgroup name in the list display."
  :type 'string
  :group 'workgroups)

(defcustom wg-display-previous-workgroup-right-decor "*"
  "String to the right of the previous workgroup name in the list display."
  :type 'string
  :group 'workgroups)

(defcustom wg-time-format "%H:%M:%S %A, %B %d %Y"
  "Format string for time display.  Passed to `format-time-string'."
  :type 'string
  :group 'workgroups)

(defcustom wg-display-battery t
  "Non-nil means include `battery', when available, in the time display."
  :type 'boolean
  :group 'workgroups)


;;; vars

(defvar wg-file nil
  "Current workgroups file.")

(defvar wg-list nil
  "List of currently defined workgroups.")

(defvar wg-dirty nil
  "Non-nil when there are unsaved changes.")

(defvar wg-kill-ring nil
  "Ring of killed or kill-ring-saved wconfigs.")

(defvar wg-minor-mode-map-entry nil
  "Contains workgroups' minor-mode-map entry.")

(defvar wg-flag-wconfig-changes t
  "Non-nil means window config changes should be flagged for undoification.")

(defvar wg-window-config-has-changed nil
  "Flag set by `window-configuration-change-hook'.")

(defvar wg-just-exited-minibuffer nil
  "Flag set by `minibuffer-exit-hook' to exempt from
undoification those window-configuration changes caused by
exiting the minibuffer .")

(defvar wg-buffer-list-filtration-on nil
  "Locally bound to t in commands that filter the buffer-list.")

(defvar wg-window-min-width 2
  "Bound to `window-min-width' when restoring wtrees. ")

(defvar wg-window-min-height 1
  "Bound to `window-min-height' when restoring wtrees.")

(defvar wg-window-min-pad 2
  "Added to `wg-window-min-foo' to produce the actual minimum window size.")

(defvar wg-actual-min-width (+ wg-window-min-width wg-window-min-pad)
  "Actual minimum window width when creating windows.")

(defvar wg-actual-min-height (+ wg-window-min-height wg-window-min-pad)
  "Actual minimum window height when creating windows.")

(defvar wg-min-edges `(0 0 ,wg-actual-min-width ,wg-actual-min-height)
  "Smallest allowable edge list of windows created by Workgroups.")

(defvar wg-null-edges '(0 0 0 0)
  "Null edge list.")

(defvar wg-morph-max-steps 200
  "Maximum `wg-morph' iterations before forcing exit.")

(defvar wg-morph-no-error t
  "Non-nil means ignore errors during `wg-morph'.
The error message is sent to *messages* instead.  This was added
when `wg-morph' was unstable, so that the screen wouldn't be left
in an inconsistent state.  It's unnecessary now, as `wg-morph' is
stable, but is left here for the time being.")

(defvar wg-last-message nil
  "Holds the last message Workgroups sent to the echo area.")

(defvar wg-selected-window nil
  "Used during wconfig restoration to hold the selected window.")

(defvar wg-face-abbrevs nil
  "Assoc list mapping face abbreviations to face names.")


;;; faces

(defmacro wg-defface (face key spec doc &rest args)
  "`defface' wrapper adding a lookup key used by `wg-fontify'."
  (declare (indent 2))
  `(progn
     (pushnew (cons ,key ',face) wg-face-abbrevs :test #'equal)
     (defface ,face ,spec ,doc ,@args)))

(wg-defface wg-current-workgroup-face :cur
  '((((class color)) (:foreground "white")))
  "Face used for the name of the current workgroup in the list display."
  :group 'workgroups)

(wg-defface wg-previous-workgroup-face :prev
  '((((class color)) (:foreground "light sky blue")))
  "Face used for the name of the previous workgroup in the list display."
  :group 'workgroups)

(wg-defface wg-other-workgroup-face :other
  '((((class color)) (:foreground "light slate grey")))
  "Face used for the names of other workgroups in the list display."
  :group 'workgroups)

(wg-defface wg-command-face :cmd
  '((((class color)) (:foreground "aquamarine")))
  "Face used for command/operation strings."
  :group 'workgroups)

(wg-defface wg-divider-face :div
  '((((class color)) (:foreground "light slate blue")))
  "Face used for dividers."
  :group 'workgroups)

(wg-defface wg-brace-face :brace
  '((((class color)) (:foreground "light slate blue")))
  "Face used for left and right braces."
  :group 'workgroups)

(wg-defface wg-message-face :msg
  '((((class color)) (:foreground "light sky blue")))
  "Face used for messages."
  :group 'workgroups)

(wg-defface wg-mode-line-face :mode
  '((((class color)) (:foreground "light sky blue")))
  "Face used for workgroup position and name in the mode-line display."
  :group 'workgroups)

(wg-defface wg-filename-face :file
  '((((class color)) (:foreground "light sky blue")))
  "Face used for filenames."
  :group 'workgroups)

(wg-defface wg-frame-face :frame
  '((((class color)) (:foreground "white")))
  "Face used for frame names."
  :group 'workgroups)


;;; utils

;; functions used in macros:
(eval-and-compile

  (defun wg-take (list n)
    "Return a list of the first N elts in LIST."
    (butlast list (- (length list) n)))

  (defun wg-partition (list n &optional step)
    "Return list of N-length sublists of LIST, offset by STEP.
Iterative to prevent stack overflow."
    (let (acc)
      (while list
        (push (wg-take list n) acc)
        (setq list (nthcdr (or step n) list)))
      (nreverse acc)))
  )

(defmacro wg-with-gensyms (syms &rest body)
  "Bind all symbols in SYMS to `gensym's, and eval BODY."
  (declare (indent 1))
  `(let (,@(mapcar (lambda (sym) `(,sym (gensym))) syms)) ,@body))

(defmacro wg-dbind (args expr &rest body)
  "Abbreviation of `destructuring-bind'."
  (declare (indent 2))
  `(destructuring-bind ,args ,expr ,@body))

(defmacro wg-dohash (spec &rest body)
  "do-style wrapper for `maphash'."
  (declare (indent 1))
  (wg-dbind (key val table &optional return) spec
    `(progn (maphash (lambda (,key ,val) ,@body) ,table) ,return)))

(defmacro wg-doconcat (spec &rest body)
  "do-style wrapper for `mapconcat'."
  (declare (indent 1))
  (wg-dbind (elt seq &optional sep) spec
    `(mapconcat (lambda (,elt) ,@body) ,seq (or ,sep ""))))

(defmacro wg-docar (spec &rest body)
  "do-style wrapper for `mapcar'."
  (declare (indent 1))
  `(mapcar (lambda (,(car spec)) ,@body) ,(cadr spec)))

(defmacro wg-get-some (spec &rest body)
  "do-style wrapper for `some'.
Returns the elt itself, rather than the return value of the form."
  (declare (indent 1))
  (wg-dbind (sym list) spec
    `(some (lambda (,sym) (when (progn ,@body) ,sym)) ,list)))

(defmacro wg-when-let (binds &rest body)
  "Like `let*', but only eval BODY when all BINDS are non-nil."
  (declare (indent 1))
  (wg-dbind (bind . binds) binds
    (when (consp bind)
      `(let (,bind)
         (when ,(car bind)
           ,(if (not binds) `(progn ,@body)
              `(wg-when-let ,binds ,@body)))))))

(defmacro wg-until (test &rest body)
  "`while' not."
  (declare (indent 1))
  `(while (not ,test) ,@body))

(defmacro wg-aif (test then &rest else)
  "Anaphoric `if'."
  (declare (indent 2))
  `(let ((it ,test)) (if it ,then ,@else)))

(defmacro wg-awhen (test &rest body)
  "Anaphoric `when'."
  (declare (indent 1))
  `(wg-aif ,test (progn ,@body)))

(defmacro wg-aand (&rest args)
  "Anaphoric `and'."
  (declare (indent defun))
  (cond ((null args) t)
        ((null (cdr args)) (car args))
        (t `(aif ,(car args) (aand ,@(cdr args))))))

(defun wg-step-to (n m step)
  "Increment or decrement N toward M by STEP.
Return M when the difference between N and M is less than STEP."
  (cond ((= n m) n)
        ((< n m) (min (+ n step) m))
        ((> n m) (max (- n step) m))))

(defun wg-within (num lo hi &optional hi-inclusive)
  "Return t when NUM is within bounds LO and HI.
HI-INCLUSIVE non-nil means the HI bound is inclusive."
  (and (>= num lo) (if hi-inclusive (<= num hi) (< num hi))))

(defun wg-filter (pred seq)
  "Return a list elements in SEQ on which PRED returns non-nil."
  (let (acc)
    (mapc (lambda (elt) (and (funcall pred elt) (push elt acc))) seq)
    (nreverse acc)))

(defun wg-last1 (list)
  "Return the last element of LIST."
  (car (last list)))

(defun wg-leave (list n)
  "Return a list of the last N elts in LIST."
  (nthcdr (- (length list) n) list))

(defun wg-rnth (n list)
  "Return the Nth element of LIST, counting from the end."
  (nth (- (length list) n 1) list))

(defun wg-insert-elt (elt list &optional pos)
  "Insert ELT into LIST at POS or the end."
  (let* ((len (length list)) (pos (or pos len)))
    (when (wg-within pos 0 len t)
      (append (wg-take list pos) (cons elt (nthcdr pos list))))))

(defun wg-move-elt (elt list pos)
  "Move ELT to position POS in LIST."
  (when (member elt list)
    (wg-insert-elt elt (remove elt list) pos)))

(defun wg-cyclic-offset-elt (elt list n)
  "Cyclically offset ELT's position in LIST by N."
  (wg-when-let ((pos (position elt list)))
    (wg-move-elt elt list (mod (+ n pos) (length list)))))

(defun wg-cyclic-nth-from-elt (elt list n)
  "Return the elt in LIST N places cyclically from ELT.
If ELT is not present is LIST, return nil."
  (wg-when-let ((pos (position elt list)))
    (nth (mod (+ pos n) (length list)) list)))

(defun wg-util-swap (elt1 elt2 list)
  "Return a copy of LIST with ELT1 and ELT2 swapped.
Return nil when ELT1 and ELT2 aren't both present."
  (wg-when-let ((p1 (position elt1 list))
                (p2 (position elt2 list)))
    (wg-move-elt elt1 (wg-move-elt elt2 list p1) p2)))

(defun wg-aget (alist key)
  "Return the value of KEY in ALIST. Uses `assq'."
  (cdr (assq key alist)))

(defun wg-acopy (alist)
  "Return a copy of ALIST's toplevel list structure."
  (wg-docar (kvp alist) (cons (car kvp) (cdr kvp))))

(defun wg-aset (alist key val)
  "Set KEY's value to VAL in ALIST.
If KEY already exists in ALIST, destructively set its value.
Otherwise, cons a new key-value-pair onto ALIST."
  (wg-aif (assq key alist) (progn (setcdr it val) alist)
    (cons (cons key val) alist)))

(defun wg-aput (alist &rest key-value-pairs)
  "Add all KEY-VALUE-PAIRS to a copy of ALIST, and return the copy."
  (flet ((rec (alist kvps) (if (not kvps) alist
                             (wg-dbind (k v . rest) kvps
                               (wg-aset (rec alist rest) k v)))))
    (rec (wg-acopy alist) key-value-pairs)))

(defun wg-get-alist (key val list-of-alists)
  "Return the first alist in LIST-OF-ALISTS containing KEY and VAL."
  (catch 'found
    (dolist (alist list-of-alists)
      (when (equal val (cdr (assoc key alist)))
        (throw 'found alist)))))

(defmacro wg-abind (alist binds &rest body)
  "Bind values in ALIST to symbols in BINDS, then eval BODY.
If an elt of BINDS is a symbol, use it as both the bound variable
and the key in ALIST.  If it is a cons, use the car as the bound
variable, and the cadr as the key."
  (declare (indent 2))
  (wg-with-gensyms (asym)
    `(let* ((,asym ,alist)
            ,@(wg-docar (bind binds)
                (let ((c (consp bind)))
                  `(,(if c (car bind) bind)
                    (wg-aget ,asym ',(if c (cadr bind) bind))))))
       ,@body)))

(defmacro wg-fill-keymap (keymap &rest binds)
  "Return KEYMAP after defining in it all keybindings in BINDS."
  (declare (indent 1))
  (wg-with-gensyms (km)
    `(let ((,km ,keymap))
       ,@(wg-docar (b (wg-partition binds 2))
           `(define-key ,km (kbd ,(car b)) ,(cadr b)))
       ,km)))

(defun wg-write-sexp-to-file (sexp file)
  "Write the printable representation of SEXP to FILE."
  (with-temp-buffer
    (let (print-level print-length)
      (insert (format "%S" sexp))
      (write-file file))))

(defun wg-read-sexp-from-file (file)
  "Read and return an sexp from FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (read (current-buffer))))

(defun wg-read-object (prompt test warning &rest args)
  "PROMPT for an object that satisfies TEST, WARNING if necessary.
ARGS are `read-from-minibuffer's args, after PROMPT."
  (let ((obj (apply #'read-from-minibuffer prompt args)))
    (wg-until (funcall test obj)
      (message warning)
      (sit-for wg-warning-timeout)
      (setq obj (apply #'read-from-minibuffer prompt args)))
    obj))


;;; workgroups utils

(defun wg-type-of (obj)
  "Return workgroups' object type of OBJ."
  (wg-aget obj 'type))

(defun wg-type-p (type obj)
  "Return t if OBJ is of type TYPE, nil otherwise."
  (and (consp obj) (eq type (wg-type-of obj))))

(defun wg-type-check (type obj &optional noerror)
  "Throw an error if OBJ is not of type TYPE."
  (or (wg-type-p type obj)
      (unless noerror
        (error "%s is not of type %s" obj type))))

(defun wg-cyclic-nth-from-frame (&optional n frame)
  "Return the frame N places away from FRAME in `frame-list' cyclically.
N defaults to 1, and FRAME defaults to `selected-frame'."
  (wg-cyclic-nth-from-elt
   (or frame (selected-frame)) (frame-list) (or n 1)))

(defun wg-add-face (facekey str)
  "Return a copy of STR fontified according to FACEKEY.
FACEKEY must be a key in `wg-face-abbrevs'."
  (let ((face (wg-aget wg-face-abbrevs facekey))
        (str  (copy-seq str)))
    (unless face (error "No face with key %s" facekey))
    (if (not wg-use-faces) str
      (put-text-property 0 (length str) 'face face str)
      str)))

(defun wg-make-string (times string &optional separator)
  "Like `make-string', but includes a separator."
  (mapconcat 'identity (make-list times string) (or separator "")))

(defmacro wg-fontify (&rest specs)
  "A small fontification DSL. *WRITEME*"
  (declare (indent defun))
  `(concat
    ,@(wg-docar (spec specs)
        (typecase spec
          (cons (if (keywordp (car spec))
                    `(wg-add-face
                      ,(car spec)
                      ,(if (stringp (cadr spec))
                           (cadr spec)
                         `(format "%s" ,(cadr spec))))
                  `(progn ,spec)))
          (string `(progn ,spec))
          (atom `(format "%s" ,spec))))))

(defun wg-error-on-active-minibuffer ()
  "Throw an error when the minibuffer is active."
  (when (active-minibuffer-window)
    (error "Workgroup operations aren't permitted while the \
minibuffer is active.")))

(defun wg-current-switch-buffer-mode ()
  "Return the buffer switching package (ido or iswitchb) to use, or nil."
  (let ((ido-p (and (boundp 'ido-mode) (memq ido-mode '(both buffer))))
        (iswitchb-p (and (boundp 'iswitchb-mode) iswitchb-mode)))
    (cond ((and ido-p iswitchb-p)
           (if (< (position 'iswitchb-mode minor-mode-map-alist :key 'car)
                  (position 'ido-mode minor-mode-map-alist :key 'car))
               'iswitchb 'ido))
          (ido-p 'ido)
          (iswitchb-p 'iswitchb)
          (t nil))))


;;; type predicates

(defun wg-buffer-p (obj)
  "Return t if OBJ is a Workgroups buffer, nil otherwise."
  (wg-type-p 'buffer obj))

(defun wg-window-p (obj)
  "Return t if OBJ is a Workgroups window, nil otherwise."
  (wg-type-p 'window obj))

(defun wg-wtree-p (obj)
  "Return t if OBJ is a Workgroups window tree, nil otherwise."
  (wg-type-p 'wtree obj))

(defun wg-wconfig-p (obj)
  "Return t if OBJ is a Workgroups window config, nil otherwise."
  (wg-type-p 'wconfig obj))

(defun wg-workgroup-p (obj)
  "Return t if OBJ is a workgroup, nil otherwise."
  (wg-type-p 'workgroup obj))


;; window config utils

;; Accessors for common fields:
(defun wg-dir   (w) (wg-aget w 'dir))
(defun wg-edges (w) (wg-aget w 'edges))
(defun wg-wlist (w) (wg-aget w 'wlist))
(defun wg-wtree (w) (wg-aget w 'wtree))

(defun wg-min-size (dir)
  "Return the minimum window size in split direction DIR."
  (if dir wg-window-min-height wg-window-min-width))

(defun wg-actual-min-size (dir)
  "Return the actual minimum window size in split direction DIR."
  (if dir wg-actual-min-height wg-actual-min-width))

(defmacro wg-with-edges (w spec &rest body)
  "Bind W's edge list to SPEC and eval BODY."
  (declare (indent 2))
  `(wg-dbind ,spec (wg-edges ,w) ,@body))

(defun wg-put-edges (w left top right bottom)
  "Return a copy of W with an edge list of LEFT TOP RIGHT and BOTTOM."
  (wg-aput w 'edges (list left top right bottom)))

(defmacro wg-with-bounds (w dir spec &rest body)
  "Bind SPEC to W's bounds in DIR, and eval BODY.
\"Bounds\" are a direction-independent way of dealing with edge lists."
  (declare (indent 3))
  (wg-with-gensyms (dir-sym l1 t1 r1 b1)
    (wg-dbind (ls1 hs1 lb1 hb1) spec
      `(wg-with-edges ,w (,l1 ,t1 ,r1 ,b1)
         (cond (,dir (let ((,ls1 ,l1) (,hs1 ,r1) (,lb1 ,t1) (,hb1 ,b1))
                       ,@body))
               (t    (let ((,ls1 ,t1) (,hs1 ,b1) (,lb1 ,l1) (,hb1 ,r1))
                       ,@body)))))))

(defun wg-put-bounds (w dir ls hs lb hb)
  "Set W's edges in DIR with bounds LS HS LB and HB."
  (if dir (wg-put-edges w ls lb hs hb) (wg-put-edges w lb ls hb hs)))

(defun wg-step-edges (edges1 edges2 hstep vstep)
  "Return W1's edges stepped once toward W2's by HSTEP and VSTEP."
  (wg-dbind (l1 t1 r1 b1) edges1
    (wg-dbind (l2 t2 r2 b2) edges2
      (let ((left (wg-step-to l1 l2 hstep))
            (top  (wg-step-to t1 t2 vstep)))
        (list left top
              (+ left (wg-step-to (- r1 l1) (- r2 l2) hstep))
              (+ top  (wg-step-to (- b1 t1) (- b2 t2) vstep)))))))

(defun wg-w-edge-operation (w edges op)
  "Return a copy of W with its edges mapped against EDGES through OP."
  (wg-aput w 'edges (mapcar* op (wg-aget w 'edges) edges)))

(defun wg-first-win (w)
  "Return the first actual window in W."
  (if (wg-window-p w) w (wg-first-win (car (wg-wlist w)))))

(defun wg-last-win (w)
  "Return the last actual window in W."
  (if (wg-window-p w) w (wg-last-win (wg-last1 (wg-wlist w)))))

(defun wg-minify-win (w)
  "Return a copy of W with the smallest allowable dimensions."
  (let* ((edges (wg-edges w))
         (left (car edges))
         (top (cadr edges)))
    (wg-put-edges w left top
                  (+ left wg-actual-min-width)
                  (+ top  wg-actual-min-height))))

(defun wg-minify-last-win (w)
  "Minify the last actual window in W."
  (wg-minify-win (wg-last-win w)))

(defun wg-wsize (w &optional height)
  "Return the width or height of W, calculated from its edge list."
  (wg-with-edges w (l1 t1 r1 b1)
    (if height (- b1 t1) (- r1 l1))))

(defun wg-adjust-wsize (w width-fn height-fn &optional new-left new-top)
  "Adjust W's width and height with WIDTH-FN and HEIGHT-FN."
  (wg-with-edges w (left top right bottom)
    (let ((left (or new-left left)) (top (or new-top top)))
      (wg-put-edges w left top
                    (+ left (funcall width-fn  (- right  left)))
                    (+ top  (funcall height-fn (- bottom top)))))))

(defun wg-scale-wsize (w width-scale height-scale)
  "Scale W's size by WIDTH-SCALE and HEIGHT-SCALE."
  (flet ((wscale (width)  (truncate (* width  width-scale)))
         (hscale (height) (truncate (* height height-scale))))
    (wg-adjust-wsize w #'wscale #'hscale)))

(defun wg-equal-wtrees (w1 w2)
  "Return t when W1 and W2 have equal structure."
  (cond ((and (wg-window-p w1) (wg-window-p w2))
         (equal (wg-edges w1) (wg-edges w2)))
        ((and (wg-wtree-p w1) (wg-wtree-p w2))
         (and (eq (wg-dir w1) (wg-dir w2))
              (equal (wg-edges w1) (wg-edges w2))
              (every #'wg-equal-wtrees (wg-wlist w1) (wg-wlist w2))))))

;; FIXME: Require a minimum size to fix wscaling
(defun wg-normalize-wtree (wtree)
  "Clean up and return a new wtree from WTREE.
Recalculate the edge lists of all subwins, and remove subwins
outside of WTREE's bounds.  If there's only one element in the
new wlist, return it instead of a new wtree."
  (if (wg-window-p wtree) wtree
    (wg-abind wtree (dir wlist)
      (wg-with-bounds wtree dir (ls1 hs1 lb1 hb1)
        (let* ((min-size (wg-min-size dir))
               (max (- hb1 1 min-size))
               (lastw (wg-last1 wlist)))
          (flet ((mapwl
                  (wl)
                  (wg-dbind (sw . rest) wl
                    (cons (wg-normalize-wtree
                           (wg-put-bounds
                            sw dir ls1 hs1 lb1
                            (setq lb1 (if (eq sw lastw) hb1
                                        (let ((hb2 (+ lb1 (wg-wsize sw dir))))
                                          (if (>= hb2 max) hb1 hb2))))))
                          (when (< lb1 max) (mapwl rest))))))
            (let ((new (mapwl wlist)))
              (if (cdr new) (wg-aput wtree 'wlist new)
                (car new)))))))))

(defun wg-scale-wtree (wtree wscale hscale)
  "Return a copy of WTREE with its dimensions scaled by WSCALE and HSCALE.
All WTREE's subwins are scaled as well."
  (let ((scaled (wg-scale-wsize wtree wscale hscale)))
    (if (wg-window-p wtree) scaled
      (wg-aput scaled
               'wlist (wg-docar (sw (wg-wlist scaled))
                        (wg-scale-wtree sw wscale hscale))))))

(defun wg-scale-wconfigs-wtree (wconfig new-width new-height)
  "Scale WCONFIG's wtree with NEW-WIDTH and NEW-HEIGHT.
Return a copy WCONFIG's wtree scaled with `wg-scale-wtree' by the
ratio or NEW-WIDTH to WCONFIG's width, and NEW-HEIGHT to
WCONFIG's height."
  (wg-normalize-wtree
   (wg-scale-wtree
    (wg-wtree wconfig)
    (/ (float new-width)  (wg-aget wconfig 'width))
    (/ (float new-height) (wg-aget wconfig 'height)))))

(defun w-set-frame-size-and-scale-wtree (wconfig &optional frame)
  "Set FRAME's size to WCONFIG's, returning a possibly scaled wtree.
If the frame size was set correctly, return WCONFIG's wtree
unchanged.  If it wasn't, return a copy of WCONFIG's wtree scaled
with `wg-scale-wconfigs-wtree' to fit the frame as it exists."
  (let ((frame (or frame (selected-frame))))
    (wg-abind wconfig ((wcwidth width) (wcheight height))
      (when window-system (set-frame-size frame wcwidth wcheight))
      (let ((fwidth  (frame-parameter frame 'width))
            (fheight (frame-parameter frame 'height)))
        (if (and (= wcwidth fwidth) (= wcheight fheight))
            (wg-wtree wconfig)
          (wg-scale-wconfigs-wtree wconfig fwidth fheight))))))

(defun wg-reverse-wlist (w &optional dir)
  "Reverse W's wlist and those of all its sub-wtrees in direction DIR.
If DIR is nil, reverse WTREE horizontally.
If DIR is 'both, reverse WTREE both horizontally and vertically.
Otherwise, reverse WTREE vertically."
  (flet ((inner (w) (if (wg-window-p w) w
                      (wg-abind w ((d1 dir) edges wlist)
                        (wg-make-wtree
                         d1 edges
                         (let ((wl2 (mapcar #'inner wlist)))
                           (if (or (eq dir 'both)
                                   (and (not dir) (not d1))
                                   (and dir d1))
                               (nreverse wl2) wl2)))))))
    (wg-normalize-wtree (inner w))))

(defun wg-reverse-wconfig (&optional dir wconfig)
  "Reverse WCONFIG's wtree's wlist in direction DIR."
  (let ((wc (or wconfig (wg-make-wconfig))))
    (wg-aput wc 'wtree (wg-reverse-wlist (wg-aget wc 'wtree) dir))))

(defun wg-wtree-move-window (wtree offset)
  "Offset `selected-window' OFFSET places in WTREE."
  (flet ((inner (w)
                (if (wg-window-p w) w
                  (wg-abind w ((d1 dir) edges wlist)
                    (wg-make-wtree
                     d1 edges
                     (wg-aif (wg-get-some (sw wlist) (wg-aget sw 'selwin))
                         (wg-cyclic-offset-elt it wlist offset)
                       (mapcar #'inner wlist)))))))
    (wg-normalize-wtree (inner wtree))))

(defun wg-wconfig-move-window (offset &optional wconfig)
  "Offset `selected-window' OFFSET places in WCONFIG."
  (let ((wc (or wconfig (wg-make-wconfig))))
    (wg-aput wc 'wtree (wg-wtree-move-window (wg-aget wc 'wtree) offset))))


;;; wconfig construction

(defun wg-window-point (ewin)
  "Return `point' or :max.  See `wg-restore-point-max'.
EWIN should be an Emacs window object."
  (let ((p (window-point ewin)))
    (if (and wg-restore-point-max (= p (point-max))) :max p)))

(defun wg-ebuf->buffer (ebuf)
  "Return a new Workgroups buffer from EBUF.
EBUF should be an Emacs buffer object"
  (with-current-buffer ebuf
    `((type        .    buffer)
      (bname       .   ,(buffer-name))
      (fname       .   ,(buffer-file-name))
      (major-mode  .   ,major-mode)
      (mark        .   ,(mark))
      (markx       .   ,mark-active))))

(defun wg-ewin->window (ewin)
  "Return a new Workgroups window from EWIN.
EWIN should be an Emacs window object."
  (let ((selwin (eq ewin (selected-window))))
    (with-selected-window ewin
      `((type     .   window)
        (buffer   .  ,(wg-ebuf->buffer (window-buffer ewin)))
        (edges    .  ,(window-edges ewin))
        (point    .  ,(wg-window-point ewin))
        (wstart   .  ,(window-start ewin))
        (hscroll  .  ,(window-hscroll ewin))
        (sbars    .  ,(window-scroll-bars ewin))
        (margins  .  ,(window-margins ewin))
        (fringes  .  ,(window-fringes ewin))
        (selwin   .  ,selwin)
        (mbswin   .  ,(eq ewin minibuffer-scroll-window))))))

(defun wg-make-wtree (dir edges wlist)
  "Return a new Workgroups wtree from DIR EDGES and WLIST."
  `((type   .   wtree)
    (dir    .  ,dir)
    (edges  .  ,edges)
    (wlist  .  ,wlist)))

(defun wg-ewtree->wtree (&optional ewtree)
  "Return a new Workgroups wtree from EWTREE or `window-tree'.
If specified, EWTREE should be an Emacs `window-tree'."
  (wg-error-on-active-minibuffer)
  (flet ((inner (ewt) (if (windowp ewt) (wg-ewin->window ewt)
                        (wg-dbind (dir edges . wins) ewt
                          (wg-make-wtree
                           dir edges (mapcar #'inner wins))))))
    (let ((ewt (car (or ewtree (window-tree)))))
      (when (and (windowp ewt) (window-minibuffer-p ewt))
        (error "Workgroups can't operate on minibuffer-only frames."))
      (inner ewt))))

(defun wg-make-wconfig ()
  "Return a new Workgroups window config from `selected-frame'."
  (message nil)
  `((type    .   wconfig)
    (left    .  ,(frame-parameter nil 'left))
    (top     .  ,(frame-parameter nil 'top))
    (width   .  ,(frame-parameter nil 'width))
    (height  .  ,(frame-parameter nil 'height))
    (sbars   .  ,(frame-parameter nil 'vertical-scroll-bars))
    (sbwid   .  ,(frame-parameter nil 'scroll-bar-width))
    (wtree   .  ,(wg-ewtree->wtree))))

(defun wg-make-blank-wconfig (&optional buffer)
  "Return a new blank wconfig.
BUFFER or `wg-default-buffer' is visible in the only window."
  (save-window-excursion
    (delete-other-windows)
    (switch-to-buffer (or buffer wg-default-buffer))
    (wg-make-wconfig)))


;;; wconfig restoration

;; FIXME: error when the file doesn't exist
(defun wg-restore-buffer (buf &optional NOERROR)
  "Switch to a buffer determined from WIN's fname and bname.
Return the buffer if it was found, nil otherwise."
  (wg-abind buf (fname bname mark markx)
    (when (cond ((and fname (file-exists-p fname))
                 (find-file fname)
                 (rename-buffer bname t))
                ((wg-awhen (get-buffer bname) (switch-to-buffer it)))
                (t (switch-to-buffer wg-default-buffer) nil))
      (set-mark mark)
      (unless markx (deactivate-mark))
      (current-buffer))))

(defun wg-restore-window (win)
  "Restore WIN in `selected-window'."
  (wg-abind win (buffer point wstart hscroll sbars fringes
                        margins selwin mbswin)
    (let ((sw (selected-window)))
      (when selwin (setq wg-selected-window sw))
      (when (wg-restore-buffer buffer)
        (set-window-start sw wstart t)
        (set-window-point
         sw (cond ((not wg-restore-point) wstart)
                  ((eq point :max) (point-max))
                  (t point)))
        (when (>= wstart (point-max)) (recenter))
        (when (and wg-restore-mbs-window mbswin)
          (setq minibuffer-scroll-window sw))
        (when wg-restore-scroll-bars
          (wg-dbind (width cols vtype htype) sbars
            (set-window-scroll-bars sw width vtype htype)))
        (when wg-restore-fringes
          (apply #'set-window-fringes sw fringes))
        (when wg-restore-margins
          (set-window-margins sw (car margins) (cdr margins)))
        (set-window-hscroll sw hscroll)))))

(defun wg-restore-wtree (wtree)
  "Restore WTREE in `selected-frame'."
  (flet ((inner (w) (if (wg-wtree-p w)
                        (wg-abind w ((d dir) wlist)
                          (let ((lastw (wg-last1 wlist)))
                            (dolist (sw wlist)
                              (unless (eq sw lastw)
                                (split-window nil (wg-wsize sw d) (not d)))
                              (inner sw))))
                      (wg-restore-window w)
                      (other-window 1))))
    (let ((window-min-width  wg-window-min-width)
          (window-min-height wg-window-min-height))
      (delete-other-windows)
      (setq wg-selected-window nil)
      (inner wtree)
      (wg-awhen wg-selected-window (select-window it)))))

;; TODO: possibly break noflag and noupdate stuff out into a wrapper
(defun wg-restore-wconfig (wconfig &optional noflag noupdate)
  "Restore WCONFIG in `selected-frame'."
  (wg-error-on-active-minibuffer)
  (let ((frame (selected-frame))
        (wg-flag-wconfig-changes nil)
        (wtree nil))
    (unless noflag
      (setq wg-window-config-has-changed t))
    (unless noupdate
      (wg-awhen (wg-current-workgroup t frame)
        (wg-update-undo-state it (wg-make-wconfig))))
    (wg-abind wconfig (left top sbars sbwid)
      (setq wtree (w-set-frame-size-and-scale-wtree wconfig frame))
      (when (and wg-restore-position left top)
        (set-frame-position frame left top))
      (when (and wg-morph-on after-init-time)
        (wg-morph (wg-ewtree->wtree) wtree wg-morph-no-error))
      (wg-restore-wtree wtree)
      (when wg-restore-scroll-bars
        (set-frame-parameter frame 'vertical-scroll-bars sbars)
        (set-frame-parameter frame 'scroll-bar-width sbwid)))))


;;; morph

(defun wg-morph-step-edges (w1 w2)
  "Step W1's edges toward W2's by `wg-morph-hsteps' and `wg-morph-vsteps'."
  (wg-step-edges (wg-edges w1) (wg-edges w2)
                 wg-morph-hsteps wg-morph-vsteps))

(defun wg-morph-determine-steps (gui-steps &optional term-steps)
  (max 1 (if (and (not window-system) term-steps) term-steps gui-steps)))

(defun wg-morph-match-wlist (wt1 wt2)
  "Return a wlist by matching WT1's wlist to WT2's.
When wlist1's and wlist2's lengths are equal, return wlist1.
When wlist1 is shorter than wlist2, add a window at the front of wlist1.
When wlist1 is longer than wlist2, package up wlist1's excess windows
into a wtree, so it's the same length as wlist2."
  (let* ((wl1 (wg-wlist wt1)) (l1 (length wl1)) (d1 (wg-dir wt1))
         (wl2 (wg-wlist wt2)) (l2 (length wl2)))
    (cond ((= l1 l2) wl1)
          ((< l1 l2)
           (cons (wg-minify-last-win (wg-rnth (1+ l1) wl2))
                 (if (< (wg-wsize (car wl1) d1)
                        (* 2 (wg-actual-min-size d1)))
                     wl1
                   (cons (wg-w-edge-operation (car wl1) wg-min-edges #'-)
                         (cdr wl1)))))
          ((> l1 l2)
           (append (wg-take wl1 (1- l2))
                   (list (wg-make-wtree d1 wg-null-edges
                                        (nthcdr (1- l2) wl1))))))))

(defun wg-morph-win->win (w1 w2 &optional swap)
  "Return a copy of W1 with its edges stepped once toward W2.
When SWAP is non-nil, return a copy of W2 instead."
  (wg-aput (if swap w2 w1) 'edges (wg-morph-step-edges w1 w2)))

(defun wg-morph-win->wtree (win wt)
  "Return a new wtree with WIN's edges and WT's last two windows."
  (wg-make-wtree
   (wg-dir wt)
   (wg-morph-step-edges win wt)
   (let ((wg-morph-hsteps 2) (wg-morph-vsteps 2))
     (wg-docar (w (wg-leave (wg-wlist wt) 2))
       (wg-morph-win->win (wg-minify-last-win w) w)))))

(defun wg-morph-wtree->win (wt win &optional noswap)
  "Grow the first window of WT and its subtrees one step toward WIN.
This eventually wipes WT's components, leaving only a window.
Swap WT's first actual window for WIN, unless NOSWAP is non-nil."
  (if (wg-window-p wt) (wg-morph-win->win wt win (not noswap))
    (wg-make-wtree
     (wg-dir wt)
     (wg-morph-step-edges wt win)
     (wg-dbind (fwin . wins) (wg-wlist wt)
       (cons (wg-morph-wtree->win fwin win noswap)
             (wg-docar (sw wins)
               (if (wg-window-p sw) sw
                 (wg-morph-wtree->win sw win t))))))))

(defun wg-morph-wtree->wtree (wt1 wt2)
  "Return a new wtree morphed one step toward WT2 from WT1.
Mutually recursive with `wg-morph-dispatch' to traverse the
structures of WT1 and WT2 looking for discrepancies."
  (let ((d1 (wg-dir wt1)) (d2 (wg-dir wt2)))
    (wg-make-wtree
     d2 (wg-morph-step-edges wt1 wt2)
     (if (not (eq (wg-dir wt1) (wg-dir wt2)))
         (list (wg-minify-last-win wt2) wt1)
       (mapcar* #'wg-morph-dispatch
                (wg-morph-match-wlist wt1 wt2)
                (wg-wlist wt2))))))

(defun wg-morph-dispatch (w1 w2)
  "Return a wtree morphed one step toward W2 from W1.
Dispatches on each possible combination of types."
  (cond ((and (wg-window-p w1) (wg-window-p w2))
         (wg-morph-win->win w1 w2 t))
        ((and (wg-wtree-p w1) (wg-wtree-p w2))
         (wg-morph-wtree->wtree w1 w2))
        ((and (wg-window-p w1) (wg-wtree-p w2))
         (wg-morph-win->wtree w1 w2))
        ((and (wg-wtree-p w1) (wg-window-p w2))
         (wg-morph-wtree->win w1 w2))))

(defun wg-morph (from to &optional noerror)
  "Morph from wtree FROM to wtree TO.
Assumes both FROM and TO fit in `selected-frame'."
  (let ((wg-morph-hsteps
         (wg-morph-determine-steps wg-morph-hsteps wg-morph-terminal-hsteps))
        (wg-morph-vsteps
         (wg-morph-determine-steps wg-morph-vsteps wg-morph-terminal-vsteps))
        (wg-flag-wconfig-changes nil)
        (wg-restore-scroll-bars nil)
        (wg-restore-fringes nil)
        (wg-restore-margins nil)
        (wg-restore-point nil)
        (truncate-partial-width-windows
         wg-morph-truncate-partial-width-windows)
        (watchdog 0))
    (condition-case err
        (wg-until (wg-equal-wtrees from to)
          (when (> (incf watchdog) wg-morph-max-steps)
            (error "`wg-morph-max-steps' exceeded"))
          (setq from (wg-normalize-wtree (wg-morph-dispatch from to)))
          (wg-restore-wtree from)
          (redisplay)
          (unless (zerop wg-morph-sit-for-seconds)
            (sit-for wg-morph-sit-for-seconds t)))
      (error (if noerror (message "%S" err) (error "%S" err))))))


;;; global error wrappers

(defun wg-file (&optional noerror)
  "Return `wg-file' or error."
  (or wg-file
      (unless noerror
        (error "Workgroups isn't visiting a file"))))

(defun wg-list (&optional noerror)
  "Return `wg-list' or error."
  (or wg-list
      (unless noerror
        (error "No workgroups are defined."))))

(defun wg-get-workgroup (key val &optional noerror)
  "Return the workgroup whose KEY equals VAL or error."
  (or (wg-get-alist key val (wg-list noerror))
      (unless noerror
        (error "There is no workgroup with an %S of %S" key val))))


;;; workgroup property ops

(defun wg-get-workgroup-prop (prop workgroup)
  "Return PROP's value in WORKGROUP."
  (wg-type-check 'workgroup workgroup)
  (wg-aget workgroup prop))

(defun wg-set-workgroup-prop (prop val workgroup &optional nodirty)
  "Set PROP to VAL in WORKGROUP, setting `wg-dirty' unless NODIRTY."
  (wg-type-check 'workgroup workgroup)
  (setcdr (assq prop workgroup) val)
  (unless nodirty (setq wg-dirty t)))

(defun wg-uid (workgroup)
  "Return WORKGROUP's uid."
  (wg-get-workgroup-prop 'uid workgroup))

(defun wg-set-uid (workgroup uid)
  "Set the uid of WORKGROUP to UID."
  (wg-set-workgroup-prop 'uid uid workgroup))

(defun wg-uids (&optional noerror)
  "Return a list of workgroups uids."
  (mapcar 'wg-uid (wg-list noerror)))

(defun wg-new-uid ()
  "Return a uid greater than any in `wg-list'."
  (let ((uids (wg-uids t)) (new -1))
    (dolist (uid uids (1+ new))
      (setq new (max uid new)))))

(defun wg-name (workgroup)
  "Return the name of WORKGROUP."
  (wg-get-workgroup-prop 'name workgroup))

(defun wg-set-name (workgroup name)
  "Set the name of WORKGROUP to NAME."
  (wg-set-workgroup-prop 'name name workgroup))

(defun wg-names (&optional noerror)
  "Return a list of workgroup names."
  (mapcar 'wg-name (wg-list noerror)))

(defun wg-buffer-list (workgroup)
  "Return the buffer-list of WORKGROUP."
  (wg-get-workgroup-prop 'buffer-list workgroup))

(defun wg-set-buffer-list (workgroup buffer-list)
  "Set the buffer-list of WORKGROUP to BUFFER-LIST."
  (wg-set-workgroup-prop 'buffer-list buffer-list workgroup))

(defun wg-buffer-names (workgroup)
  "Return a list of the names of WORKGROUP's buffers."
  (mapcar (lambda (buf) (wg-aget buf 'bname)) (wg-buffer-list workgroup)))

(defun wg-filters (workgroup)
  "Return the filter list of WORKGROUP."
  (wg-get-workgroup-prop 'filters workgroup))

(defun wg-set-filters (workgroup filters)
  "Set the filter list of WORKGROUP to FILTERS."
  (wg-set-workgroup-prop 'filters filters workgroup))

(defun wg-add-filter (workgroup filter)
  "Add FILTER to WORKGROUP's filter list."
  (let ((filters (append (wg-filters workgroup) (list filter))))
    (wg-set-filters workgroup filters)))

(defun wg-remove-filter (workgroup filter)
  "Remove FILTER from WORKGROUP's filter list."
  (let ((filters (remove filter (wg-filters workgroup))))
    (wg-set-filters workgroup filters)))


;;; current and previous workgroup ops

(defun wg-current-workgroup (&optional noerror frame)
  "Return the current workgroup."
  (or (wg-awhen (frame-parameter frame 'wg-current-workgroup-uid)
        (wg-get-workgroup 'uid it noerror))
      (unless noerror
        (error "There's no current workgroup in this frame."))))

(defun wg-set-current-workgroup (workgroup &optional frame)
  "Set the current workgroup to WORKGROUP."
  (set-frame-parameter
   frame 'wg-current-workgroup-uid (when workgroup (wg-uid workgroup))))

(defun wg-workgroup-is-current-p (workgroup &optional noerror)
  "Return t when WORKGROUP is the current workgroup, nil otherwise."
  (wg-awhen (wg-current-workgroup noerror)
    (eq it workgroup)))

(defun wg-previous-workgroup (&optional noerror frame)
  "Return the previous workgroup."
  (or (wg-awhen (frame-parameter frame 'wg-previous-workgroup-uid)
        (wg-get-workgroup 'uid it noerror))
      (unless noerror
        (error "There's no previous workgroup in this frame."))))

(defun wg-set-previous-workgroup (workgroup &optional frame)
  "Set the previous workgroup to WORKGROUP."
  (set-frame-parameter
   frame 'wg-previous-workgroup-uid (when workgroup (wg-uid workgroup))))


;;; base config

(defun wg-set-base-config (workgroup config)
  "Set the base config of WORKGROUP to CONFIG."
  (wg-set-workgroup-prop 'wconfig config workgroup))

(defun wg-base-config (workgroup)
  "Return the base config of WORKGROUP."
  (wg-get-workgroup-prop 'wconfig workgroup))


;;; working config undoification

(defun wg-workgroup-table (&optional frame)
  "Return FRAME's workgroup table, creating it first if necessary."
  (or (frame-parameter frame 'wg-workgroup-table)
      (let ((wt (make-hash-table)))
        (set-frame-parameter frame 'wg-workgroup-table wt)
        wt)))

(defun wg-workgroup-state-table (workgroup &optional frame)
  "Return FRAME's WORKGROUP's state table."
  (let ((uid (wg-uid workgroup)) (wt (wg-workgroup-table frame)))
    (or (gethash uid wt)
        (let ((wst (make-hash-table)))
          (puthash 'undo-pointer 0 wst)
          (puthash 'undo-list (list (wg-base-config workgroup)) wst)
          (puthash uid wst wt)
          wst))))

(defmacro wg-with-undo (workgroup spec &rest body)
  "Bind WORKGROUP's undo state to SPEC and eval BODY."
  (declare (indent 2))
  (wg-dbind (state-table undo-pointer undo-list) spec
    `(let* ((,state-table (wg-workgroup-state-table ,workgroup))
            (,undo-pointer (gethash 'undo-pointer ,state-table))
            (,undo-list (gethash 'undo-list ,state-table)))
       ,@body)))

(defun wg-undo-state (workgroup)
  "Return the current undo state of WORKGROUP."
  (wg-with-undo workgroup (state-table undo-pointer undo-list)
    (nth undo-pointer undo-list)))

(defun wg-update-undo-state (workgroup config)
  "Set the working config of WORKGROUP to CONFIG."
  (wg-with-undo workgroup (state-table undo-pointer undo-list)
    (setcar (nthcdr undo-pointer undo-list) config)))

(defun wg-push-new-undo-state (workgroup config)
  "Push CONFIG onto WORKGROUP's undo list, truncating its future if necessary."
  (wg-with-undo workgroup (state-table undo-pointer undo-list)
    (let ((undo-list (cons config (nthcdr undo-pointer undo-list))))
      (when (and wg-wconfig-undo-list-max
                 (> (length undo-list) wg-wconfig-undo-list-max))
        (setq undo-list (wg-take undo-list wg-wconfig-undo-list-max)))
      (puthash 'undo-list undo-list state-table)
      (puthash 'undo-pointer 0 state-table))))


;;; undo/redo hook functions
;;
;; Exempting minibuffer-related window-config changes from undoification is
;; tricky, which is why all the flag-setting hooks.
;;
;; Example hook call order:
;;
;; pre-command-hook called ido-switch-buffer
;; window-configuration-change-hook called
;; minibuffer-setup-hook called
;; post-command-hook called
;; pre-command-hook called self-insert-command
;; post-command-hook called
;; ...
;; pre-command-hook called self-insert-command
;; post-command-hook called
;; pre-command-hook called ido-exit-minibuffer
;; minibuffer-exit-hook called
;; window-configuration-change-hook called [2 times]
;; post-command-hook called
;;

(defun wg-unflag-window-config-has-changed ()
  "Reset `wg-window-config-has-changed' to nil to exempt from
undoification those window-configuration changes caused by
entering the minibuffer."
  (setq wg-window-config-has-changed nil))

(defun wg-flag-just-exited-minibuffer ()
  "Set `wg-just-exited-minibuffer' on minibuffer exit."
  (setq wg-just-exited-minibuffer t))

(defun wg-flag-wconfig-change ()
  "Conditionally set `wg-window-config-has-changed' to t.
Added to `window-configuration-change-hook'."
  (when (and wg-flag-wconfig-changes
             (zerop (minibuffer-depth))
             (not wg-just-exited-minibuffer))
    (setq wg-window-config-has-changed t))
  (setq wg-just-exited-minibuffer nil))

(defun wg-update-undo-state-before-command ()
  "`wg-update-undo-state' before `wg-commands-that-alter-window-configs'.
Added to `pre-command-hook'."
  (when (memq this-command wg-commands-that-alter-window-configs)
    (wg-awhen (wg-current-workgroup t)
      (wg-update-undo-state it (wg-make-wconfig)))))

(defun wg-push-new-undo-state-after-command ()
  "`wg-push-new-undo-state' when `wg-window-config-has-changed' is non-nil.
Added to `post-command-hook'."
  (when (and wg-window-config-has-changed (zerop (minibuffer-depth)))
    (wg-awhen (wg-current-workgroup t)
      (wg-push-new-undo-state it (wg-make-wconfig))))
  (setq wg-window-config-has-changed nil))


;;; workgroup construction and restoration

;; (defun wg-make-workgroup (uid name wconfig)
;;   "Return a new workgroup from UID, NAME and WCONFIG."
;;   `((type         .   workgroup)
;;     (uid          .  ,uid)
;;     (name         .  ,name)
;;     (wconfig      .  ,wconfig)
;;     (buffer-list  .   nil)))

(defun wg-make-workgroup (uid name wconfig)
  "Return a new workgroup from UID, NAME and WCONFIG."
  `((type         .   workgroup)
    (uid          .  ,uid)
    (name         .  ,name)
    (wconfig      .  ,wconfig)
    (buffer-list  .   nil)
    (filters      .   nil)))

(setq wg-list (mapcar (lambda (wg) (append wg '((filters)))) wg-list))

(defun wg-make-default-workgroup (name)
  "Return a new workgroup named NAME with wconfig `wg-make-wconfig'."
  (wg-make-workgroup nil name (wg-make-wconfig)))

(defun wg-make-blank-workgroup (name &optional buffer)
  "Return a new blank workgroup named NAME, optionally viewing BUFFER."
  (wg-make-workgroup nil name (wg-make-blank-wconfig buffer)))

(defun wg-restore-workgroup (workgroup)
  "Restore WORKGROUP in `selected-frame'."
  (let ((buffer-list (wg-get-workgroup-prop 'buffer-list workgroup)))
    (dolist (buf buffer-list)
      (wg-awhen (wg-aget buf 'fname)
        (find-file-noselect it))))
  (wg-restore-wconfig (wg-undo-state workgroup) t))


;;; workgroups list ops

(defun wg-delete (workgroup)
  "Remove WORKGROUP from `wg-list'.
Also delete all references to it by `wg-workgroup-table',
`wg-current-workgroup' and `wg-previous-workgroup'."
  (dolist (frame (frame-list))
    (remhash (wg-uid workgroup) (wg-workgroup-table frame))
    (when (eq workgroup (wg-current-workgroup t frame))
      (wg-set-current-workgroup nil frame))
    (when (eq workgroup (wg-previous-workgroup t frame))
      (wg-set-previous-workgroup nil frame)))
  (setq wg-list (remove workgroup (wg-list)) wg-dirty t))

(defun wg-add (new &optional pos)
  "Add WORKGROUP to `wg-list'.
If a workgroup with the same name exists, overwrite it."
  (wg-awhen (wg-get-workgroup 'name (wg-name new) t)
    (unless pos (setq pos (position it wg-list)))
    (wg-delete it))
  (wg-set-uid new (wg-new-uid))
  (setq wg-dirty t wg-list (wg-insert-elt new wg-list pos)))

(defun wg-check-and-add (workgroup)
  "Add WORKGROUP to `wg-list'.
Query to overwrite if a workgroup with the same name exists."
  (let ((name (wg-name workgroup)))
    (when (wg-get-workgroup 'name name t)
      (unless (or wg-no-confirm
                  (y-or-n-p (format "%S exists. Overwrite? " name)))
        (error "Cancelled"))))
  (wg-add workgroup))

(defun wg-cyclic-offset-workgroup (workgroup n)
  "Offset WORKGROUP's position in `wg-list' by N."
  (wg-aif (wg-cyclic-offset-elt workgroup (wg-list) n)
      (setq wg-list it wg-dirty t)
    (error "Workgroup isn't present in `wg-list'.")))

(defun wg-list-swap (w1 w2)
  "Swap the positions of W1 and W2 in `wg-list'."
  (when (eq w1 w2) (error "Can't swap a workgroup with itself"))
  (wg-aif (wg-util-swap w1 w2 (wg-list))
      (setq wg-list it wg-dirty t)
    (error "Both workgroups aren't present in `wg-list'.")))


;; ;;; buffer list ops
;; (defun wg-wtree-buffer-list (wtree)
;;   "Return a list of unique buffer names visible in WTREE."
;;   (flet ((rec (w) (if (wg-window-p w) (list (wg-aget w 'bname))
;;                     (mapcan #'rec (wg-wlist w)))))
;;     (remove-duplicates (rec wtree) :test #'equal)))
;; (defun wg-workgroup-buffer-list (workgroup)
;;   "Call `wg-wconfig-buffer-list' on WORKGROUP's working config."
;;   (wg-wtree-buffer-list (wg-wtree (wg-undo-state workgroup))))
;; (defun wg-buffer-list ()
;;   "Call `wg-workgroup-buffer-list' on all workgroups in `wg-list'."
;;   (remove-duplicates
;;    (mapcan #'wg-workgroup-buffer-list (wg-list t))
;;    :test #'equal))
;; (defun wg-find-buffer (bname)
;;   "Return the first workgroup in which a buffer named BNAME is visible."
;;   (wg-get-some (wg (wg-list))
;;     (member bname (wg-workgroup-buffer-list wg))))


;;; mode-line

(defun wg-mode-line-string ()
  "Return the string to be displayed in the mode-line."
  (let ((cur (wg-current-workgroup t)))
    (cond (cur (wg-fontify " "
                 (:div wg-mode-line-left-brace)
                 (:mode (position cur (wg-list t)))
                 (:div wg-mode-line-divider)
                 (:mode (wg-name cur))
                 (:div wg-mode-line-right-brace)))
          (t   (wg-fontify " "
                 (:div wg-mode-line-left-brace)
                 (:mode "No workgroups")
                 (:div wg-mode-line-right-brace))))))

(defun wg-mode-line-add-display ()
  "Add Workgroups' mode-line format to `mode-line-format'."
  (unless (assq 'wg-mode-line-on mode-line-format)
    (let ((format `(wg-mode-line-on (:eval (wg-mode-line-string))))
          (pos (1+ (position 'mode-line-position mode-line-format))))
      (set-default 'mode-line-format
                   (wg-insert-elt format mode-line-format pos)))))

(defun wg-mode-line-remove-display ()
  "Remove Workgroups' mode-line format from `mode-line-format'."
  (wg-awhen (assq 'wg-mode-line-on mode-line-format)
    (set-default 'mode-line-format (remove it mode-line-format))
    (force-mode-line-update)))


;;; minibuffer reading

;; (completing-read
;; (ido-completing-read
;; (iswitchb-read-buffer
;; (ido-read-buffer "foo: ")
;; (iswitchb-read-buffer "foo: ")

(defun wg-completing-read
  (prompt choices &optional pred rm ii history default)
  "Do a completing read.  The function called depends on what's on."
  (case (wg-current-switch-buffer-mode)
    (ido (ido-completing-read prompt choices pred rm ii history default))
    (iswitchb
     (let* ((iswitchb-use-virtual-buffers nil)
            (iswitchb-make-buflist-hook
             (lambda () (setq iswitchb-temp-buflist choices))))
       (iswitchb-read-buffer prompt default rm)))
    (t (completing-read prompt choices pred rm ii history default))))

(defun wg-read-workgroup (&optional noerror)
  "Read a workgroup with `wg-completing-read'."
  (wg-get-workgroup
   'name
   (wg-completing-read
    "Workgroup: " (wg-names) nil nil nil nil
    (wg-awhen (wg-current-workgroup t) (wg-name it)))
   noerror))

(defun wg-read-buffer ()
  "Read with `wg-completing-read' and return a buffer name."
  (get-buffer
   (wg-completing-read "Buffer: " (mapcar 'buffer-name (buffer-list)))))

(defun wg-read-new-workgroup-name (&optional prompt)
  "Read a non-empty name string from the minibuffer."
  (wg-read-object
   (or prompt "Name: ")
   (lambda (obj) (and (stringp obj) (not (equal obj ""))))
   "Please enter a unique, non-empty name"))

(defun wg-read-workgroup-index ()
  "Prompt for the index of a workgroup."
  (let ((max (1- (length (wg-list)))))
    (wg-read-object
     (format "%s\n\nEnter [0-%d]: " (wg-disp) max)
     (lambda (obj) (and (integerp obj) (wg-within obj 0 max t)))
     (format "Please enter an integer [%d-%d]" 0 max)
     nil nil t)))


;;; messaging

(defun wg-msg (format-string &rest args)
  "Call `message' with FORMAT-STRING and ARGS.
Also save the msg to `wg-last-message'."
  (setq wg-last-message (apply #'message format-string args)))

(defmacro wg-fontified-msg (&rest format)
  "`wg-fontify' FORMAT and call `wg-msg' on it."
  (declare (indent defun))
  `(wg-msg (wg-fontify ,@format)))


;;; command utils

(defun wg-arg (&optional reverse noerror)
  "Return a workgroup one way or another.
For use in interactive forms.  If `current-prefix-arg' is nil,
return the current workgroup.  Otherwise read a workgroup from
the minibuffer.  If REVERSE is non-nil, `current-prefix-arg's
begavior is reversed."
  (wg-list noerror)
  (if (if reverse (not current-prefix-arg) current-prefix-arg)
      (wg-read-workgroup noerror)
    (wg-current-workgroup noerror)))

(defun wg-add-to-kill-ring (config)
  "Add CONFIG to `wg-kill-ring'."
  (push config wg-kill-ring)
  (setq wg-kill-ring (wg-take wg-kill-ring wg-kill-ring-size)))

(defun wg-disp ()
  "Return the Workgroups list display string.
The string contains the names of all workgroups in `wg-list',
decorated with faces, dividers and strings identifying the
current and previous workgroups."
  (let ((wl    (wg-list t))
        (cur   (wg-current-workgroup  t))
        (prev  (wg-previous-workgroup t))
        (div   (wg-add-face :div wg-display-divider))
        (cld   wg-display-current-workgroup-left-decor)
        (crd   wg-display-current-workgroup-right-decor)
        (pld   wg-display-previous-workgroup-left-decor)
        (prd   wg-display-previous-workgroup-right-decor)
        (i     -1))
    (wg-fontify
      (:brace wg-display-left-brace)
      (if (not wl) (wg-fontify (:msg "No workgroups are defined"))
        (wg-doconcat (w wl div)
          (let ((str (format "%d: %s" (incf i) (wg-name w))))
            (cond ((eq w cur)
                   (wg-fontify (:cur (concat cld str crd))))
                  ((eq w prev)
                   (wg-fontify (:prev (concat pld str prd))))
                  (t (wg-fontify (:other str)))))))
      (:brace wg-display-right-brace))))

(defun wg-cyclic-nth-from-workgroup (&optional workgroup n)
  "Return the workgroup N places from WORKGROUP in `wg-list'."
  (wg-when-let ((wg (or workgroup (wg-current-workgroup t))))
    (wg-cyclic-nth-from-elt wg (wg-list) (or n 1))))


;; per-workgroup buffer-list stuff

(defun wg-wgbuf-refers-to-p (wgbuf buffer-or-name)
  "Return t if WGBUF refers to BUFFER-OR-NAME, nil otherwise."
  (let ((wg-fname (wg-aget wgbuf 'fname))
        (ebuf (get-buffer buffer-or-name)))
    (cond (wg-fname (equal wg-fname (buffer-file-name ebuf)))
          ((buffer-file-name ebuf) nil)
          ((equal (wg-aget wgbuf 'bname) (buffer-name ebuf))))))

(defun wg-get-corresponding-wgbuf (buffer-or-name workgroup)
  "Return the wgbuf in WORKGROUP's buffer list corresponding to EBUF."
  (catch 'found
    (dolist (wgbuf (wg-buffer-list workgroup))
      (when (wg-wgbuf-refers-to-p wgbuf buffer-or-name)
        (throw 'found wgbuf)))))

(defun wg-workgroup-live-buffers (workgroup &optional buffers)
  "Filter BUFFERS-OR-NAMES by WORKGROUP's live buffers' names."
  (wg-filter (lambda (b) (wg-get-corresponding-wgbuf b workgroup))
             (or buffers (mapcar 'buffer-name (buffer-list)))))

(defun wg-filter-buffer-list (workgroup &optional buffers)
  "Run WORKGROUP's filters, optionally seeding with BUFFERS."
  (let ((wg-temp-buffer-list (wg-workgroup-live-buffers workgroup buffers)))
    (dolist (filter (wg-filters workgroup) wg-temp-buffer-list)
      (condition-case err
          (cond ((symbolp filter) (funcall filter))
                ((atom filter) (error "Invalid filter type"))
                ((eq (car filter) 'lambda) (funcall (eval filter)))
                (t (eval filter)))
        (error
         (let ((msg (format "Error in workgroup %S filter %S - %S"
                            (wg-name workgroup) filter (cadr err))))
           (if (not wg-message-on-filter-errors) (error msg)
             (message msg)
             (sit-for wg-warning-timeout))))))))

;; Custom buffer-list filter example:
;;
;; (defun wg-add-irc-channel-buffers ()
;;   (dolist (buffer-name (mapcar 'buffer-name (buffer-list)))
;;     (when (string-match "#" buffer-name)
;;       (pushnew buffer-name wg-temp-buffer-list))))
;;
;; (wg-add-filter (wg-current-workgroup) 'wg-add-irc-channel-buffers)
;; (wg-remove-filter (wg-current-workgroup) 'wg-add-irc-channel-buffers)

(defun wg-filter-ido-buffer-list ()
  "Set `ido-temp-list' to only the current workgroup's live buffers."
  (when (and wg-buffer-list-filtration-on (boundp 'ido-temp-list))
    (wg-awhen (wg-current-workgroup t)
      (setq ido-temp-list
            (wg-filter-buffer-list it ido-temp-list)))))

(defun wg-filter-iswitchb-buffer-list ()
  "Set `iswitchb-temp-buflist' to only the current workgroup's live buffers."
  (when wg-buffer-list-filtration-on
    (wg-awhen (wg-current-workgroup t)
      (setq iswitchb-temp-buflist
            (wg-filter-buffer-list it iswitchb-temp-buflist)))))

(defun wg-add-buffer-to-workgroup (ebuf workgroup &optional force)
  "Add EBUF to WORKGROUP's buffer list."
  (interactive (list (wg-read-buffer) (wg-read-workgroup) current-prefix-arg))
  (let ((buflist (wg-buffer-list workgroup))
        (wgname (wg-name workgroup))
        (bname (buffer-name ebuf)))
    (wg-awhen (wg-get-corresponding-wgbuf ebuf workgroup)
      (if force (setq buflist (remove it buflist))
        (error "%S has already been added to %s" bname wgname)))
    (wg-set-buffer-list workgroup (cons (wg-ebuf->buffer ebuf) buflist))
    (message "Added %S to %s" bname wgname)))

(defun wg-remove-buffer-from-workgroup (ebuf workgroup)
  "Remove EBUF from WORKGROUP's buffer list."
  (interactive (list (wg-read-buffer) (wg-read-workgroup)))
  (let ((wgbuf (wg-get-corresponding-wgbuf ebuf workgroup))
        (wgname (wg-name workgroup))
        (bname (buffer-name ebuf)))
    (unless wgbuf (error "%S is not a member of %s" bname wgname))
    (wg-set-buffer-list workgroup (remove wgbuf (wg-buffer-list workgroup)))
    (message "Removed %S from %s" bname wgname)))

(defun wg-add-current-buffer-to-current-workgroup ()
  "Do what the name says."
  (interactive)
  (wg-add-buffer-to-workgroup
   (current-buffer) (wg-current-workgroup)))

(defun wg-remove-current-buffer-from-current-workgroup ()
  "Do what the name says."
  (interactive)
  (wg-remove-buffer-from-workgroup
   (current-buffer) (wg-current-workgroup)))


;;; iswitchb compatibility

(defun wg-iswitchb-internal (&optional method prompt default init)
  "Provide the buffer switching interface to
`iswitchb-read-buffer' (analogous to ido's `ido-buffer-internal')
that iswitchb *should* have.  Most this code is duplicated from
`iswitchb', so is similarly shitty."
  (let* ((iswitchb-method (or method iswitchb-default-method))
         (iswitchb-invalid-regexp nil)
         (buf (when 'iswitchb-read-buffer
                (iswitchb-read-buffer
                 (or prompt "iswitch ") default nil init))))
    (cond ((eq iswitchb-exit 'findfile)
           (call-interactively 'find-file))
          (iswitchb-invalid-regexp
           (message "Won't make invalid regexp named buffer"))
          (t (when buf
               (if (get-buffer buf) (iswitchb-visit-buffer buf)
                 (iswitchb-possible-new-buffer buf)))))))


;;; buffer list filtration

(defvar wg-bind-cycle-filtration nil
  "Non-nil means bind `wg-cycle-filtration' on minibuffer setup.")

(defun wg-cycle-filtration ()
  "When point is directly after the prompt, toggle filtration.
Otherwise, call `backward-char'.  Bound to C-b in `iswitchb-mode-map'."
  (interactive)
  (if (> (point) (minibuffer-prompt-end)) (backward-char)
    (throw 'cycle-filtration (minibuffer-contents))))

(defun wg-bind-cycle-filtration-hook ()
  "Conditionally bind C-b to `wg-cycle-filtration'.
Added to `minibuffer-setup-hook'."
  (when wg-bind-cycle-filtration
    (local-set-key (kbd "C-b") 'wg-cycle-filtration)))

(defun wg-switch-to-buffer-prompt (&optional workgroup)
  "Return a prompt string indicating WORKGROUP and filtration status."
  (format "%s [%s]: "
          (if wg-buffer-list-filtration-on "Filtered" "Unfiltered")
          (wg-name (or workgroup (wg-current-workgroup)))))

(defun wg-filtration-on (state)
  "Return non-nil when STATE implies filtration of completions."
  (ecase state
    (filtered t)
    (unfiltered nil)
    (fallback nil)
    (off nil)))

(defun wg-ido-switch-buffer (method current-state)
  "Completion filtration interface to `ido-switch-buffer'."
  (if (eq current-state 'off) (ido-switch-buffer)
    (let ((wg-buffer-list-filtration-on (wg-filtration-on current-state)))
      (ido-buffer-internal method nil (wg-switch-to-buffer-prompt)))))

(defun wg-iswitchb-buffer (method current-state)
  "Completion filtration interface to `iswitchb-buffer'."
  (if (eq current-state 'off) (iswitchb-buffer)
    (let ((wg-buffer-list-filtration-on (wg-filtration-on current-state)))
      (wg-iswitchb-internal method (wg-switch-to-buffer-prompt)))))

(defun wg-fallback-switch-to-buffer (method current-state)
  "Completion filtration interface to `switch-to-buffer'."
  (let ((read-buffer-function nil))
    (call-interactively
     (case method
       (other-window 'switch-to-buffer-other-window)
       (other-frame  'switch-to-buffer-other-frame)
       (otherwise    'switch-to-buffer)))))

(defun wg-switch-buffer-function (&optional state)
  "Return the correct switch buffer fallback function."
  (case (if (eq state 'fallback) 'fallback
          (wg-current-switch-buffer-mode))
    (fallback  'wg-fallback-switch-to-buffer)
    (ido       'wg-ido-switch-buffer)
    (iswitchb  'wg-iswitchb-buffer)))

(defun wg-switch-to-buffer (&optional method)
  "Switch to a buffer.  Call the current switch buffer function,
completing on either all buffer names then current workgroup
buffer names, or current workgroup buffer names then all buffer
names.  See `wg-switch-buffer-filter-order'."
  (interactive)
  (if (or (not wg-switch-buffer-filter-order)
          (not (wg-current-workgroup t)))
      (funcall (wg-switch-buffer-function) method 'off)
    (let* ((wg-bind-cycle-filtration t)
           (order wg-switch-buffer-filter-order)
           (len (length order))
           (counter -1)
           (done nil))
      (while (not done)
        (let ((state (nth (mod (incf counter) len) order)))
          (catch 'cycle-filtration
            (funcall (wg-switch-buffer-function state) method state)
            (setq done t)))))))

(defun wg-switch-to-buffer-other-window ()
  ""
  (interactive)
  (wg-switch-to-buffer 'other-window))

(defun wg-switch-to-buffer-other-frame ()
  ""
  (interactive)
  (wg-switch-to-buffer 'other-frame))

(defun wg-next-buffer ()
  (interactive)
  (let* ((wg (wg-current-workgroup))
         (wg-bufs (wg-buffer-list wg))
         (buf (current-buffer)))
    ))


;;; commands

(defun wg-switch-to-workgroup (workgroup)
  "Switch to WORKGROUP."
  (interactive (list (wg-read-workgroup)))
  (wg-awhen (wg-current-workgroup t)
    (when (eq it workgroup) (error "Already on: %s" (wg-name it))))
  (wg-restore-workgroup workgroup)
  (wg-awhen (wg-current-workgroup t) (wg-set-previous-workgroup it))
  (wg-set-current-workgroup workgroup)
  (run-hooks 'wg-switch-hook)
  (wg-fontified-msg (:cmd "Switched:  ") (wg-disp)))

(defun wg-create-workgroup (name)
  "Create and add a workgroup named NAME.
If workgroups already exist, create a blank workgroup.  If no
workgroups exist yet, create a workgroup from the current window
configuration."
  (interactive (list (wg-read-new-workgroup-name)))
  (let ((w (if (wg-current-workgroup t) (wg-make-blank-workgroup name)
             (wg-make-default-workgroup name))))
    (wg-check-and-add w)
    (wg-switch-to-workgroup w)
    (wg-fontified-msg (:cmd "Created: ") (:cur name) "  " (wg-disp))))

(defun wg-clone-workgroup (workgroup name)
  "Create and add a clone of WORKGROUP named NAME."
  (interactive (list (wg-arg) (wg-read-new-workgroup-name)))
  (let ((new (wg-make-workgroup nil name (wg-base-config workgroup))))
    (wg-check-and-add new)
    (wg-update-undo-state new (wg-undo-state workgroup))
    (wg-switch-to-workgroup new)
    (wg-fontified-msg
      (:cmd "Cloned: ") (:cur (wg-name workgroup))
      (:msg " to ") (:cur name) "  " (wg-disp))))

(defun wg-kill-workgroup (workgroup)
  "Kill WORKGROUP, saving its working config to the kill ring."
  (interactive (list (wg-arg)))
  (wg-add-to-kill-ring (wg-undo-state workgroup))
  (let ((to (or (wg-previous-workgroup t)
                (wg-cyclic-nth-from-workgroup workgroup))))
    (wg-delete workgroup)
    (if (eq to workgroup)
        (wg-restore-wconfig (wg-make-blank-wconfig))
      (wg-switch-to-workgroup to))
    (wg-fontified-msg
      (:cmd "Killed: ") (:cur (wg-name workgroup)) "  " (wg-disp))))

(defun wg-kill-ring-save-base-config (workgroup)
  "Save WORKGROUP's base config to `wg-kill-ring'."
  (interactive (list (wg-arg)))
  (wg-add-to-kill-ring (wg-base-config workgroup))
  (wg-fontified-msg
    (:cmd "Saved: ") (:cur (wg-name workgroup))
    (:cur "'s ") (:msg "base config to the kill ring")))

(defun wg-kill-ring-save-working-config (workgroup)
  "Save WORKGROUP's working config to `wg-kill-ring'."
  (interactive (list (wg-arg)))
  (wg-add-to-kill-ring (wg-undo-state workgroup))
  (wg-fontified-msg
    (:cmd "Saved: ") (:cur (wg-name workgroup))
    (:cur "'s ") (:msg "working config to the kill ring")))

(defun wg-yank-wconfig ()
  "Restore a wconfig from `wg-kill-ring'.
Successive yanks restore wconfigs sequentially from the kill
ring, starting at the front."
  (interactive)
  (unless wg-kill-ring (error "The kill-ring is empty"))
  (let ((pos (if (not (eq real-last-command 'wg-yank-wconfig)) 0
               (mod (1+ (or (get 'wg-yank-wconfig :position) 0))
                    (length wg-kill-ring)))))
    (put 'wg-yank-wconfig :position pos)
    (wg-restore-wconfig (nth pos wg-kill-ring))
    (wg-fontified-msg (:cmd "Yanked: ") (:msg pos) "  " (wg-disp))))

(defun wg-kill-workgroup-and-buffers (workgroup)
  "Kill WORKGROUP and the buffers in its working config."
  (interactive (list (wg-arg)))
  (let ((bufs (save-window-excursion
                (wg-restore-workgroup workgroup)
                (mapcar #'window-buffer (window-list)))))
    (wg-kill-workgroup workgroup)
    (mapc #'kill-buffer bufs)
    (wg-fontified-msg
      (:cmd "Killed: ") (:cur (wg-name workgroup))
      (:msg " and its buffers ") "\n" (wg-disp))))

(defun wg-delete-other-workgroups (workgroup)
  "Delete all workgroups but WORKGROUP."
  (interactive (list (wg-arg)))
  (unless (or wg-no-confirm (y-or-n-p "Really delete all other workgroups? "))
    (error "Cancelled"))
  (let ((cur (wg-current-workgroup)))
    (mapc #'wg-delete (remove workgroup (wg-list)))
    (unless (eq workgroup cur) (wg-switch-to-workgroup workgroup))
    (wg-fontified-msg
      (:cmd "Deleted: ") (:msg "All workgroups but ")
      (:cur (wg-name workgroup)))))

(defun wg-update-workgroup (workgroup)
  "Set the base config of WORKGROUP to its working config in `selected-frame'."
  (interactive (list (wg-arg)))
  (wg-set-base-config workgroup (wg-undo-state workgroup))
  (wg-fontified-msg
    (:cmd "Updated: ") (:cur (wg-name workgroup))))

(defun wg-update-all-workgroups ()
  "Update all workgroups' base configs.
Worgroups are updated with their working configs in the
`selected-frame'."
  (interactive)
  (mapc #'wg-update-workgroup (wg-list))
  (wg-fontified-msg (:cmd "Updated: ") (:msg "All")))

(defun wg-revert-workgroup (workgroup)
  "Set the working config of WORKGROUP to its base config in `selected-frame'."
  (interactive (list (wg-arg)))
  (if (wg-workgroup-is-current-p workgroup t)
      (wg-restore-wconfig (wg-base-config workgroup))
    (wg-push-new-undo-state workgroup (wg-base-config workgroup)))
  (wg-fontified-msg (:cmd "Reverted: ") (:cur (wg-name workgroup))))

(defun wg-revert-all-workgroups ()
  "Revert all workgroups to their base configs."
  (interactive)
  (mapc #'wg-revert-workgroup (wg-list))
  (wg-fontified-msg (:cmd "Reverted: ") (:msg "All")))

(defun wg-switch-to-index (n)
  "Switch to Nth workgroup in `wg-list'."
  (interactive (list (or current-prefix-arg (wg-read-workgroup-index))))
  (let ((wl (wg-list)))
    (wg-switch-to-workgroup
     (or (nth n wl) (error "There are only %d workgroups" (length wl))))))

;; Define wg-switch-to-index-[0-9]:
(macrolet
    ((defi (n)
       `(defun ,(intern (format "wg-switch-to-index-%d" n)) ()
          ,(format "Switch to the workgroup at index %d in the list." n)
          (interactive) (wg-switch-to-index ,n))))
  (defi 0) (defi 1) (defi 2) (defi 3) (defi 4)
  (defi 5) (defi 6) (defi 7) (defi 8) (defi 9))

(defun wg-switch-left (&optional workgroup n)
  "Switch to the workgroup left of WORKGROUP in `wg-list'."
  (interactive (list (wg-arg nil t) current-prefix-arg))
  (wg-switch-to-workgroup
   (or (wg-cyclic-nth-from-workgroup workgroup (or n -1))
       (car (wg-list)))))

(defun wg-switch-right (&optional workgroup n)
  "Switch to the workgroup right of WORKGROUP in `wg-list'."
  (interactive (list (wg-arg nil t) current-prefix-arg))
  (wg-switch-to-workgroup
   (or (wg-cyclic-nth-from-workgroup workgroup n)
       (car (wg-list)))))

(defun wg-switch-left-other-frame (&optional n)
  "Like `wg-switch-left', but operates on the next frame."
  (interactive "p")
  (with-selected-frame (wg-cyclic-nth-from-frame (or n 1))
    (wg-switch-left)))

(defun wg-switch-right-other-frame (&optional n)
  "Like `wg-switch-right', but operates on the next frame."
  (interactive "p")
  (with-selected-frame (wg-cyclic-nth-from-frame (or n -1))
    (wg-switch-right)))

(defun wg-switch-to-previous-workgroup ()
  "Switch to the previous workgroup."
  (interactive)
  (wg-switch-to-workgroup (wg-previous-workgroup)))

(defun wg-swap-workgroups ()
  "Swap the previous and current workgroups."
  (interactive)
  (wg-list-swap (wg-current-workgroup) (wg-previous-workgroup))
  (wg-fontified-msg (:cmd "Swapped ") (wg-disp)))

(defun wg-offset-left (workgroup &optional n)
  "Offset WORKGROUP leftward in `wg-list' cyclically."
  (interactive (list (wg-arg) current-prefix-arg))
  (wg-cyclic-offset-workgroup workgroup (or n -1))
  (wg-fontified-msg (:cmd "Offset left: ") (wg-disp)))

(defun wg-offset-right (workgroup &optional n)
  "Offset WORKGROUP rightward in `wg-list' cyclically."
  (interactive (list (wg-arg) current-prefix-arg))
  (wg-cyclic-offset-workgroup workgroup (or n 1))
  (wg-fontified-msg (:cmd "Offset right: ") (wg-disp)))

(defun wg-rename-workgroup (workgroup newname)
  "Rename WORKGROUP to NEWNAME."
  (interactive (list (wg-arg) (wg-read-new-workgroup-name "New name: ")))
  (let ((oldname (wg-name workgroup)))
    (wg-set-name workgroup newname)
    (wg-fontified-msg
      (:cmd "Renamed: ") (:cur oldname) (:msg " to ")
      (:cur (wg-name workgroup)))))

(defun wg-reset (&optional force)
  "Reset workgroups.
Deletes all state saved in frame parameters, and nulls out
`wg-list', `wg-file' and `wg-kill-ring'."
  (interactive "P")
  (unless (or force wg-no-confirm (y-or-n-p "Are you sure? "))
    (error "Canceled"))
  (dolist (frame (frame-list))
    (set-frame-parameter frame 'wg-workgroup-table nil)
    (set-frame-parameter frame 'wg-current-workgroup-uid nil)
    (set-frame-parameter frame 'wg-previous-workgroup-uid nil))
  (setq wg-list nil wg-file nil wg-dirty nil)
  (wg-fontified-msg (:cmd "Reset: ") (:msg "Workgroups")))


;;; undo/redo

(defun wg-timeline-string (position length)
  "Return a timeline visualization string from POSITION and LENGTH."
  (wg-fontify
    (:div "-<(")
    (:other (wg-make-string (- length position) "-" "="))
    (:cur "O")
    (:other (wg-make-string (1+ position) "-" "="))
    (:div ")>-")))

(defun wg-undo-wconfig-change (&optional offset)
  "Undo a change to the current workgroup's window-configuration."
  (interactive "P")
  (wg-with-undo (wg-current-workgroup) (utab upos ulst)
    (let ((upos (+ upos (or offset 1))) (len (length ulst)) (msg ""))
      (if (>= upos len) (setq msg "  Completely undone!")
        (wg-restore-wconfig (nth upos ulst) t)
        (setf (gethash 'undo-pointer utab) upos))
      (wg-fontified-msg (:cmd "Undo: ")
        (wg-timeline-string (gethash 'undo-pointer utab) len)
        (:cur msg)))))

(defun wg-redo-wconfig-change (&optional offset)
  "Redo a change to the current workgroup's window-configuration."
  (interactive "P")
  (wg-with-undo (wg-current-workgroup) (utab upos ulst)
    (let ((upos (- upos (or offset 1))) (len (length ulst)) (msg ""))
      (if (< upos 0) (setq msg "  Completely redone!")
        (wg-restore-wconfig (nth upos ulst) t)
        (setf (gethash 'undo-pointer utab) upos))
      (wg-fontified-msg (:cmd "Redo: ")
        (wg-timeline-string (gethash 'undo-pointer utab) len)
        (:cur msg)))))


;;; file commands

(defun wg-save (file)
  "Save workgroups to FILE.
Called interactively with a prefix arg, or if `wg-file'
is nil, read a filename.  Otherwise use `wg-file'."
  (interactive
   (list (if (or current-prefix-arg (not (wg-file t)))
             (read-file-name "File: ") (wg-file))))
  (if (not wg-dirty) (message "(No workgroups need to be saved)")
    (wg-write-sexp-to-file
     `(,wg-persisted-workgroups-tag
       ,wg-persisted-workgroups-format-version
       ,@(wg-list))
     file)
    (setq wg-dirty nil wg-file file)
    (wg-fontified-msg (:cmd "Wrote: ") (:file file))))

(defun wg-load (file)
  "Load workgroups from FILE.
Called interactively with a prefix arg, and if `wg-file'
is non-nil, use `wg-file'. Otherwise read a filename."
  (interactive
   (list (if (and current-prefix-arg (wg-file t))
             (wg-file) (read-file-name "File: "))))
  (let ((contents (wg-read-sexp-from-file file)))
    (unless (consp contents)
      (error "%S is not a workgroups file." file))
    (wg-dbind (tag version . workgroups-list) contents
      (unless (eq tag wg-persisted-workgroups-tag)
        (error "%S is not a workgroups file." file))
      (unless (and (stringp version)
                   (string= version wg-persisted-workgroups-format-version))
        (error "%S is incompatible with this version of Workgroups.  \
Please create a new workgroups file." file))
      (wg-reset t)
      (setq wg-list workgroups-list wg-file file)))
  (when wg-switch-on-load
    (wg-awhen (wg-list t)
      (wg-switch-to-workgroup (car it))))
  (wg-fontified-msg (:cmd "Loaded: ") (:file file)))

(defun wg-find-file (file)
  "Create a new workgroup and find file FILE in it."
  (interactive "FFile: ")
  (wg-create-workgroup (file-name-nondirectory file))
  (find-file file))

(defun wg-find-file-read-only (file)
  "Create a new workgroup and find FILE read-only in it."
  (interactive "FFile: ")
  (wg-create-workgroup (file-name-nondirectory file))
  (find-file-read-only file))

;; (defun wg-get-by-buffer (buf)
;;   "Switch to the first workgroup in which BUF is visible."
;;   (interactive (list (wg-read-buffer)))
;;   (wg-aif (wg-find-buffer buf) (wg-switch-to-workgroup it)
;;     (error "No workgroup contains %S" buf)))

(defun wg-dired (dir &optional switches)
  "Create a workgroup and open DIR in dired with SWITCHES."
  (interactive (list (read-directory-name "Dired: ") current-prefix-arg))
  (wg-create-workgroup dir)
  (dired dir switches))


;;; mode-line commands

(defun wg-toggle-mode-line ()
  "Toggle Workgroups' mode-line display."
  (interactive)
  (setq wg-mode-line-on (not wg-mode-line-on))
  (force-mode-line-update)
  (wg-fontified-msg
    (:cmd "mode-line: ") (:msg (if wg-mode-line-on "on" "off"))))


;;; morph commands

(defun wg-toggle-morph ()
  "Toggle `wg-morph', Workgroups' morphing animation."
  (interactive)
  (setq wg-morph-on (not wg-morph-on))
  (wg-fontified-msg
    (:cmd "Morph: ") (:msg (if wg-morph-on "on" "off"))))


;;; Window movement commands

(defun wg-backward-transpose-window (offset)
  "Move `selected-window' backward by OFFSET in its wlist."
  (interactive (list (or current-prefix-arg -1)))
  (wg-restore-wconfig (wg-wconfig-move-window offset)))

(defun wg-transpose-window (offset)
  "Move `selected-window' forward by OFFSET in its wlist."
  (interactive (list (or current-prefix-arg 1)))
  (wg-restore-wconfig (wg-wconfig-move-window offset)))

(defun wg-reverse-frame-horizontally ()
  "Reverse the order of all horizontally split wtrees."
  (interactive)
  (wg-restore-wconfig (wg-reverse-wconfig)))

(defun wg-reverse-frame-vertically ()
  "Reverse the order of all vertically split wtrees."
  (interactive)
  (wg-restore-wconfig (wg-reverse-wconfig t)))

(defun wg-reverse-frame-horizontally-and-vertically ()
  "Reverse the order of all wtrees."
  (interactive)
  (wg-restore-wconfig (wg-reverse-wconfig 'both)))


;;; echo commands

(defun wg-echo-current-workgroup ()
  "Display the name of the current workgroup in the echo area."
  (interactive)
  (wg-fontified-msg
    (:cmd "Current: ") (:cur (wg-name (wg-current-workgroup)))))

(defun wg-echo-all-workgroups ()
  "Display the names of all workgroups in the echo area."
  (interactive)
  (wg-fontified-msg (:cmd "Workgroups: ") (wg-disp)))

(defun wg-echo-time ()
  "Echo the current time.  Optionally includes `battery' info."
  (interactive)
  (wg-msg ;; Pass through format to escape the % in `battery'
   "%s" (wg-fontify
          (:cmd "Current time: ")
          (:msg (format-time-string wg-time-format))
          (when (and wg-display-battery (fboundp 'battery))
            (wg-fontify "\n" (:cmd "Battery: ") (:msg (battery)))))))

(defun wg-echo-version ()
  "Echo Workgroups' current version number."
  (interactive)
  (wg-fontified-msg
    (:cmd "Workgroups version: ") (:msg wg-version)))

(defun wg-echo-last-message ()
  "Echo the last message Workgroups sent to the echo area.
The string is passed through a format arg to escape %'s."
  (interactive)
  (message "%s" wg-last-message))


;;; help

(defvar wg-help
  '("\\[wg-switch-to-workgroup]"
    "Switch to a workgroup"
    "\\[wg-create-workgroup]"
    "Create a new workgroup and switch to it"
    "\\[wg-clone-workgroup]"
    "Create a clone of the current workgroug and switch to it"
    "\\[wg-kill-workgroup]"
    "Kill a workgroup"
    "\\[wg-kill-ring-save-base-config]"
    "Save the current workgroup's base config to the kill ring"
    "\\[wg-kill-ring-save-working-config]"
    "Save the current workgroup's working config to the kill ring"
    "\\[wg-yank-wconfig]"
    "Yank a wconfig from the kill ring into the current frame"
    "\\[wg-kill-workgroup-and-buffers]"
    "Kill a workgroup and all buffers visible in it"
    "\\[wg-delete-other-workgroups]"
    "Delete all but the specified workgroup"
    "\\[wg-update-workgroup]"
    "Update a workgroup's base config with its working config"
    "\\[wg-update-all-workgroups]"
    "Update all workgroups' base configs with their working configs"
    "\\[wg-revert-workgroup]"
    "Revert a workgroup's working config to its base config"
    "\\[wg-revert-all-workgroups]"
    "Revert all workgroups' working configs to their base configs"
    "\\[wg-switch-to-index]"
    "Jump to a workgroup by its index in the workgroups list"
    "\\[wg-switch-to-index-0]"
    "Switch to the workgroup at index 0"
    "\\[wg-switch-to-index-1]"
    "Switch to the workgroup at index 1"
    "\\[wg-switch-to-index-2]"
    "Switch to the workgroup at index 2"
    "\\[wg-switch-to-index-3]"
    "Switch to the workgroup at index 3"
    "\\[wg-switch-to-index-4]"
    "Switch to the workgroup at index 4"
    "\\[wg-switch-to-index-5]"
    "Switch to the workgroup at index 5"
    "\\[wg-switch-to-index-6]"
    "Switch to the workgroup at index 6"
    "\\[wg-switch-to-index-7]"
    "Switch to the workgroup at index 7"
    "\\[wg-switch-to-index-8]"
    "Switch to the workgroup at index 8"
    "\\[wg-switch-to-index-9]"
    "Switch to the workgroup at index 9"
    "\\[wg-switch-left]"
    "Switch to the workgroup leftward cyclically in the workgroups list"
    "\\[wg-switch-right]"
    "Switch to the workgroup rightward cyclically in the workgroups list"
    "\\[wg-switch-left-other-frame]"
    "Like `wg-switch-left', but operates in the next frame"
    "\\[wg-switch-right-other-frame]"
    "Like `wg-switch-right', but operates in the next frame"
    "\\[wg-switch-to-previous-workgroup]"
    "Switch to the previously selected workgroup"
    "\\[wg-swap-workgroups]"
    "Swap the positions of the current and previous workgroups"
    "\\[wg-offset-left]"
    "Offset a workgroup's position leftward cyclically in the workgroups list"
    "\\[wg-offset-right]"
    "Offset a workgroup's position rightward cyclically in the workgroups list"
    "\\[wg-rename-workgroup]"
    "Rename a workgroup"
    "\\[wg-reset]"
    "Reset Workgroups' entire state."
    "\\[wg-save]"
    "Save the workgroup list to a file"
    "\\[wg-load]"
    "Load a workgroups list from a file"
    "\\[wg-find-file]"
    "Create a new blank workgroup and find a file in it"
    "\\[wg-find-file-read-only]"
    "Create a new blank workgroup and find a file read-only in it"
    ;; "\\[wg-get-by-buffer]"
    ;; "Switch to the workgroup and config in which the specified buffer is visible"
    "\\[wg-dired]"
    "Create a new blank workgroup and open a dired buffer in it"
    "\\[wg-backward-transpose-window]"
    "Move `selected-window' backward in its wlist"
    "\\[wg-transpose-window]"
    "Move `selected-window' forward in its wlist"
    "\\[wg-reverse-frame-horizontally]"
    "Reverse the order of all horizontall window lists."
    "\\[wg-reverse-frame-vertically]"
    "Reverse the order of all vertical window lists."
    "\\[wg-reverse-frame-horizontally-and-vertically]"
    "Reverse the order of all window lists."
    "\\[wg-toggle-mode-line]"
    "Toggle Workgroups' mode-line display"
    "\\[wg-toggle-morph]"
    "Toggle the morph animation on any wconfig change"
    "\\[wg-echo-current-workgroup]"
    "Display the name of the current workgroup in the echo area"
    "\\[wg-echo-all-workgroups]"
    "Display the names of all workgroups in the echo area"
    "\\[wg-echo-time]"
    "Display the current time in the echo area"
    "\\[wg-echo-version]"
    "Display the current version of Workgroups in the echo area"
    "\\[wg-echo-last-message]"
    "Display the last message Workgroups sent to the echo area in the echo area."
    "\\[wg-help]"
    "Show this help message")
  "List of commands and their help messages. Used by `wg-help'.")

(defun wg-help ()
  "Display Workgroups' help buffer."
  (interactive)
  (with-output-to-temp-buffer "*workroups help*"
    (princ  "Workgroups' keybindings:\n\n")
    (dolist (elt (wg-partition wg-help 2))
      (wg-dbind (cmd help-string) elt
        (princ (format "%15s   %s\n"
                       (substitute-command-keys cmd)
                       help-string))))))


;;; keymap


(defvar wg-map
  (wg-fill-keymap (make-sparse-keymap)

    ;; workgroup creation

    "C-c"        'wg-create-workgroup
    "c"          'wg-create-workgroup
    "C"          'wg-clone-workgroup


    ;; killing and yanking

    "C-k"        'wg-kill-workgroup
    "k"          'wg-kill-workgroup
    "M-W"        'wg-kill-ring-save-base-config
    "M-w"        'wg-kill-ring-save-working-config
    "C-y"        'wg-yank-wconfig
    "y"          'wg-yank-wconfig
    "M-k"        'wg-kill-workgroup-and-buffers
    "K"          'wg-delete-other-workgroups


    ;; updating and reverting

    "C-u"        'wg-update-workgroup
    "u"          'wg-update-workgroup
    "C-S-u"      'wg-update-all-workgroups
    "U"          'wg-update-all-workgroups
    "C-r"        'wg-revert-workgroup
    "r"          'wg-revert-workgroup
    "C-S-r"      'wg-revert-all-workgroups
    "R"          'wg-revert-all-workgroups


    ;; workgroup switching

    "C-'"        'wg-switch-to-workgroup
    "'"          'wg-switch-to-workgroup
    "C-v"        'wg-switch-to-workgroup
    "v"          'wg-switch-to-workgroup
    "C-j"        'wg-switch-to-index
    "j"          'wg-switch-to-index
    "0"          'wg-switch-to-index-0
    "1"          'wg-switch-to-index-1
    "2"          'wg-switch-to-index-2
    "3"          'wg-switch-to-index-3
    "4"          'wg-switch-to-index-4
    "5"          'wg-switch-to-index-5
    "6"          'wg-switch-to-index-6
    "7"          'wg-switch-to-index-7
    "8"          'wg-switch-to-index-8
    "9"          'wg-switch-to-index-9
    "C-p"        'wg-switch-left
    "p"          'wg-switch-left
    "C-n"        'wg-switch-right
    "n"          'wg-switch-right
    "M-p"        'wg-switch-left-other-frame
    "M-n"        'wg-switch-right-other-frame
    "C-a"        'wg-switch-to-previous-workgroup
    "a"          'wg-switch-to-previous-workgroup


    ;; undo/redo

    "<left>"     'wg-undo-wconfig-change
    "<right>"    'wg-redo-wconfig-change
    "["          'wg-undo-wconfig-change
    "]"          'wg-redo-wconfig-change


    ;; buffer-list

    "o"          'wg-add-current-buffer-to-current-workgroup
    "O"          'wg-remove-current-buffer-from-current-workgroup
    "M-o"        'wg-toggle-per-workgroup-buffer-lists


    ;; workgroup movement

    "C-x"        'wg-swap-workgroups
    "C-,"        'wg-offset-left
    "C-."        'wg-offset-right


    ;; file and buffer

    "C-s"        'wg-save
    "C-l"        'wg-load
    "C-f"        'wg-find-file
    "S-C-f"      'wg-find-file-read-only
    ;; "C-b"        'wg-get-by-buffer
    ;; "b"          'wg-get-by-buffer
    "C-b"        'wg-switch-to-buffer
    "b"          'wg-switch-to-buffer
    "d"          'wg-dired


    ;; window moving and frame reversal

    "<"          'wg-backward-transpose-window
    ">"          'wg-transpose-window
    "|"          'wg-reverse-frame-horizontally
    "-"          'wg-reverse-frame-vertically
    "+"          'wg-reverse-frame-horizontally-and-vertically


    ;; toggling

    "C-i"        'wg-toggle-mode-line
    "C-w"        'wg-toggle-morph


    ;; echoing

    "S-C-e"      'wg-echo-current-workgroup
    "E"          'wg-echo-current-workgroup
    "C-e"        'wg-echo-all-workgroups
    "e"          'wg-echo-all-workgroups
    "C-t"        'wg-echo-time
    "t"          'wg-echo-time
    "V"          'wg-echo-version
    "C-m"        'wg-echo-last-message
    "m"          'wg-echo-last-message


    ;; misc

    "A"          'wg-rename-workgroup
    "!"          'wg-reset
    "?"          'wg-help

    )
  "Workgroups' keymap.")


;;; mode definition

(defun wg-unset-prefix-key ()
  "Restore the original definition of `wg-prefix-key'."
  (wg-awhen (get 'wg-prefix-key :original)
    (wg-dbind (key . def) it
      (when (eq wg-map (lookup-key global-map key))
        (global-set-key key def))
      (put 'wg-prefix-key :original nil))))

(defun wg-set-prefix-key ()
  "Define `wg-prefix-key' as `wg-map' in `global-map'."
  (wg-unset-prefix-key)
  (let ((key wg-prefix-key))
    (put 'wg-prefix-key :original (cons key (lookup-key global-map key)))
    (global-set-key key wg-map)))

(defun wg-query-for-save ()
  "Query for save when `wg-dirty' is non-nil."
  (or (not wg-dirty)
      (not (y-or-n-p "Save modified workgroups? "))
      (call-interactively 'wg-save)
      t))

(defun wg-emacs-exit-query ()
  "Conditionally call `wg-query-for-save'.
Call `wg-query-for-save' when `wg-query-for-save-on-emacs-exit'
is non-nil."
  (or (not wg-query-for-save-on-emacs-exit)
      (wg-query-for-save)))

(defun wg-workgroups-mode-exit-query ()
  "Conditionally call `wg-query-for-save'.
Call `wg-query-for-save' when
`wg-query-for-save-on-workgroups-mode-exit' is non-nil."
  (or (not wg-query-for-save-on-workgroups-mode-exit)
      (wg-query-for-save)))

(define-minor-mode workgroups-mode
  "This turns `workgroups-mode' on and off.
If ARG is null, toggle `workgroups-mode'.
If ARG is an integer greater than zero, turn on `workgroups-mode'.
If ARG is an integer less one, turn off `workgroups-mode'.
If ARG is anything else, turn on `workgroups-mode'."
  :lighter     " wg"
  :init-value  nil
  :global      t
  :group       'workgroups
  (cond
   (workgroups-mode
    (add-hook 'kill-emacs-query-functions 'wg-emacs-exit-query)
    (add-hook 'window-configuration-change-hook 'wg-flag-wconfig-change)
    (add-hook 'pre-command-hook 'wg-update-undo-state-before-command)
    (add-hook 'post-command-hook 'wg-push-new-undo-state-after-command)
    (add-hook 'minibuffer-setup-hook 'wg-unflag-window-config-has-changed)
    (add-hook 'minibuffer-setup-hook 'wg-bind-cycle-filtration-hook)
    (add-hook 'minibuffer-exit-hook 'wg-flag-just-exited-minibuffer)
    (add-hook 'ido-make-buffer-list-hook 'wg-filter-ido-buffer-list)
    (add-hook 'iswitchb-make-buflist-hook 'wg-filter-iswitchb-buffer-list)
    (wg-set-prefix-key)
    (wg-mode-line-add-display)
    (let ((map (make-sparse-keymap)))
      (define-key map
        [remap switch-to-buffer] 'wg-switch-to-buffer)
      (define-key map
        [remap switch-to-buffer-other-window]
        'wg-switch-to-buffer-other-window)
      (define-key map
        [remap switch-to-buffer-other-frame]
        'wg-switch-to-buffer-other-frame)
      (if wg-minor-mode-map-entry
          (setcdr wg-minor-mode-map-entry map)
        (setq wg-minor-mode-map-entry (cons 'workgroups-mode map))
        (add-to-list 'minor-mode-map-alist wg-minor-mode-map-entry))))
   (t
    (wg-workgroups-mode-exit-query)
    (remove-hook 'kill-emacs-query-functions 'wg-emacs-exit-query)
    (remove-hook 'window-configuration-change-hook 'wg-flag-wconfig-change)
    (remove-hook 'pre-command-hook 'wg-update-undo-state-before-command)
    (remove-hook 'post-command-hook 'wg-push-new-undo-state-after-command)
    (remove-hook 'minibuffer-setup-hook 'wg-unflag-window-config-has-changed)
    (remove-hook 'minibuffer-setup-hook 'wg-bind-cycle-filtration-hook)
    (remove-hook 'minibuffer-exit-hook 'wg-flag-just-exited-minibuffer)
    (remove-hook 'ido-make-buffer-list-hook 'wg-filter-ido-buffer-list)
    (remove-hook 'iswitchb-make-buflist-hook 'wg-filter-iswitchb-buffer-list)
    (wg-unset-prefix-key)
    (wg-mode-line-remove-display))))


;;; provide

(provide 'workgroups)


;;; workgroups.el ends here
