;; $Id: recips.cl,v 1.14 2003/07/08 18:05:25 layer Exp $

(in-package :user)

;;; Functions to locate/categorize recipients

(defstruct recip
  type ;; :prog, :file, :error, :bad, :include   nil means normal
  orig ;; unparsed
  addr ;; parsed
  file ;; for :file and :prog recips
  prog-user ;; for :prog recips
  errmsg ;; for :error and :bad recips
  escaped ;; don't expand any further
  expanded-from ;; string  (information only)
  owner ;; nil means just use the original envelope sender
  mailer ;; which delivery program should be used
  status) 

(defun error-recip-p (r)
  (and (recip-p r) (eq (recip-type r) :error)))

(defun bad-recip-p (r)
  (eq (recip-type r) :bad))

(defun include-recip-p (r)
  (eq (recip-type r) :include))

(defun file-recip-p (r)
  (eq (recip-type r) :file))

(defun prog-recip-p (r)
  (eq (recip-type r) :prog))


(defun recip-printable (r)
  (let ((type (recip-type r)))
    (if (null type)
	(emailaddr-orig (recip-addr r))
      (ecase type
	(:prog
	    (with-output-to-string (s)
	      (write-char #\| s)
	      (if (recip-prog-user r)
		  (format s "(~A)" (recip-prog-user r)))
	      (write-string (recip-file r) s)))
	(:file
	 (recip-file r))
	(:include
	 (format nil ":include:~A" (recip-file r)))
	(:error
	 (if (recip-addr r)
	     (emailaddr-orig (recip-addr r))
	   (format nil ":error:~A" (recip-errmsg r))))
	(:bad
	 (format nil ":bad:~A" (recip-orig r)))))))
  

(defun local-domain-p (address)
  (let ((domain (emailaddr-domain address)))
    (or (null domain) 
	(member domain 
		(append (list (short-host-name) (fqdn)) 
			*host-aliases*
			*localdomains*)
		:test #'equalp))))




(defun string-or-recip-or-emailaddr-to-emailaddr (thing)
  (block nil
    (when (recip-p thing)
      (if (recip-type thing)
	  (error "lookup-recipient doesn't work on special recips")
	(return (recip-addr thing))))
    (make-parsed-and-unparsed-address thing)))
    

  
;; accepts non-special recip structs as arg as well
(defun get-recipient-disposition (thing)
  (block nil
    (let ((addr (string-or-recip-or-emailaddr-to-emailaddr thing)))
      (if (not (local-domain-p addr))
	  (return :non-local))

      ;; lookup-recipient might return error information.
      (let ((res (multiple-value-list (quick-verify-recip addr))))
	(if (null (first res))
	    (return :local-unknown))
	
	(when (eq (first res) :error)
	  (return (values-list res)))
	
	(return :local-ok)))))


    

;; Only call on potential local recips.
(defun quick-verify-recip (thing)
  (block nil
    (let* ((addr (string-or-recip-or-emailaddr-to-emailaddr thing))
	   (expansion (expand-alias addr)))
      (when expansion
	(if (every #'error-recip-p expansion)
	    (return (values :error (recip-errmsg (first expansion))))
	  (return t)))
      
      (any-mailer-matches-p addr))))


;; Returns a list of recips.  There may be duplicates.  There
;; may be error recips.  
(defun lookup-recip (thing)
  (block nil
    (let ((addr (string-or-recip-or-emailaddr-to-emailaddr thing))
	  expansion)
      (if (not (local-domain-p addr))
	  (return (list (make-recip :addr addr :mailer :smtp))))
      
      (setf expansion (alias-transform thing))
      
      (dolist (recip expansion)
	(mark-recip-with-suitable-mailer recip))
      
      expansion)))

	
(defmacro mailing-list-p (exp)
  `(> (length ,exp) 1))

;; returns a list of recip structs w/ no duplicates.
;; There may be some :error recips.
(defun expand-addresses (addrs sender &key metoo)
  (let ((exclude-sender t)
	(sender-exp (lookup-recip sender)))
    (if (or metoo
	    (mailing-list-p sender-exp)
	    (recip-type (first sender-exp))) ;; prog/file/whatnot expansion    
	(setf exclude-sender nil)
      (setf sender-exp (first sender-exp)))
    
    (let (recips)
      (dolist (addr addrs)
	(setf addr (make-parsed-and-unparsed-address addr))
	(let ((expansion (lookup-recip addr)))
	  (when (and (mailing-list-p expansion)
		     exclude-sender
		     (member sender-exp expansion :test #'same-recip-p))
	    (setf expansion 
	      (delete sender-exp expansion :test #'same-recip-p)))
	  
	  (setf recips (nconc recips expansion))))

      (delete-duplicates recips :test #'same-recip-p))))

;; Should be called on post-expansion recip structs.
(defun same-recip-p (recip1 recip2)
  (block nil
    (let ((type1 (recip-type recip1))
	  (type2 (recip-type recip2)))
      (if (not (eq type1 type2))
	  (return nil))
      (when (null type1) ;; regular recips
	(let* ((addr1 (recip-addr recip1))
	       (addr2 (recip-addr recip2))
	       (local1 (local-domain-p addr1))
	       (local2 (local-domain-p addr2)))
	  ;; If the user parts don't match, definite non-match
	  (if (not (equalp (emailaddr-user addr1) (emailaddr-user addr2)))
	      (return nil))
	  ;; If they're both local, then we have a match.
	  (if (and local1 local2)
	      (return t))
	  ;; If both are non-local, compare the domain parts
	  (if (and (not local1) (not local2))
	      (return (equalp (emailaddr-domain addr1) 
			      (emailaddr-domain addr2))))
	  ;; One local, one non-local.  Definite non-match
	  (return nil)))
      ;; other recip types
      (ecase type1
	(:prog
	    (and
	     (string= (recip-file recip1) (recip-file recip2))
	     (equalp (recip-prog-user recip1) (recip-prog-user recip2))))
	(:file
	 (string= (recip-file recip1) (recip-file recip2)))
	(:error
	 ;; error recips are for bad addresses.. so compare addresses
	 (emailaddr= (recip-addr recip1) (recip-addr recip2)))))))

;;; recipient parsing stuff.  

;; Works with specials, atoms, and quoted strings.
(defun tokens-begin-with-p (char tokens)
  (let ((token (first tokens)))
    (when tokens
      (cond
       ((atom-token-p token)
	(char= (schar (second token) 0) char))
       ((quoted-string-token-p token)
	(char= (schar (second token) 1) char))
       ((some-special-token-p token char)
	t)
       (t
	nil)))))

(defun collect-tokens-up-to-comma (tokens)
  (let (res)
    (while (and tokens (not (comma-token-p (first tokens))))
      (push (pop tokens) res))
    (values (nreverse res) tokens)))

(defun parse-special-recip (tokens)
  (block nil
    (multiple-value-bind (tokens remainder)
	(collect-tokens-up-to-comma tokens)
      (let* ((string (tokens-to-string tokens :strip-trailing-white t))
	     (recip (make-recip :orig string)))
	(cond
	 ;; file recips
	 ((tokens-begin-with-p #\/ tokens)
	  (setf (recip-type recip) :file)
	  (setf (recip-file recip) string))

	 ;; include recips
	 ((prefix-of-p ":include:" string)
	  (setf (recip-type recip) :include)
	  (setf (recip-file recip) (subseq string #.(length ":include:"))))
       
	 ;; error recips
	 ((prefix-of-p ":error:" string)
	  (setf (recip-type recip) :error)
	  (setf (recip-errmsg recip) (subseq string #.(length ":error:")))
	  (if (string= (recip-errmsg recip) "")
	      (setf (recip-errmsg recip) "No such mailbox")))
       
	 ;; program recips
	 ((tokens-begin-with-p #\| tokens)
	  (setf (recip-type recip) :prog)
	  (multiple-value-bind (found whole prog-user prog)
	      (match-regexp "^|(\\([^)]+\\))\\(.*\\)" string)
	    (declare (ignore whole))
	    (if* found
	       then
		    (setf (recip-file recip) prog)
		    (setf (recip-prog-user recip) prog-user)
	       else
		    (setf (recip-file recip) (subseq string 1)))))
	 (t
	  (return)))
	
	(values recip remainder)))))

(defun make-string-from-tokens-up-to-comma (tokens)
  (multiple-value-bind (tokens remainder)
      (collect-tokens-up-to-comma tokens)
    (values (tokens-to-string tokens) remainder)))

;; we're really at a proper ending if, after skipping whitespace and comments,
;; we see no more tokens.. or a comma
(defun at-end-of-recip-p (tokens)
  (setf tokens (skip-cfws tokens))
  (or (null tokens) (comma-token-p (first tokens))))


(defun make-recip-from-mailbox (mb &key allow-null escaped)
  (let ((recip (make-recip :escaped escaped))
	addr)
    (setf (recip-orig recip)
      (with-output-to-string (s)
	(print-address mb s)))
    
    (setf addr (mailbox-to-emailaddr mb))
    (setf (recip-addr recip) addr)
    
    ;; check for <>
    (cond
     ((and (null (emailaddr-user addr)) (null (emailaddr-domain addr))
	   (not allow-null))
      (setf (recip-type recip) :bad)
      (setf (recip-errmsg recip) "Invalid address"))
     
     ;; check for @domain.com
     ((and (null (emailaddr-user addr))
	   (emailaddr-domain addr))
      (setf (recip-type recip) :bad)
      (setf (recip-errmsg recip) "User address required")))
    
    recip))
	      

;; Returns a list of recip structs (since a group may have more
;; than one)
(defun parse-regular-recip (tokens &key allow-null)
  (let (escaped)
    ;; check for escaped recip
    (when (tokens-begin-with-p #\\ tokens)
      (pop tokens)
      (setf escaped t))
    (multiple-value-bind (parsed remainder)
	(parse-address tokens)
      (if* (or (null parsed) (not (at-end-of-recip-p remainder)))
	 then
	      ;; couldn't parse
	      (multiple-value-bind (string remainder)
		  (make-string-from-tokens-up-to-comma tokens)
		(values
		 (list
		  (make-recip :type :bad
			      :orig string
			      :errmsg "Invalid address"))
		 remainder))
	 else
	      (let ((mblist (if (groupspec-p (second parsed))
				(second 
				 (groupspec-mailbox-list (second parsed)))
			      (list (second parsed)))))
		(values 
		 (mapcar #'(lambda (mb)
			     (make-recip-from-mailbox mb
						      :allow-null allow-null
						      :escaped escaped))
			 mblist)
		 remainder))))))

(defun parse-recip-list (input &key (pos 0) allow-null)
  (block nil
    (let ((tokens (emailaddr-lex input :pos pos))
	  recips)
      (loop
	;; skip and leading whitespace, comments, and commas
	(while (and tokens
		    (or (whitespace-token-p (first tokens))
			(comment-token-p (first tokens))
			(comma-token-p (first tokens))))
	  (pop tokens))
	
	(if (null tokens) 
	    (return))
	
	;; Check for special stuff first.
	(multiple-value-bind (recip remainder)
	    (parse-special-recip tokens)
	  (if* recip
	     then
		  (push recip recips)
		  (setf tokens remainder)
	     else
		  ;; try regular recip
		  (multiple-value-bind (new-recips remainder)
		      (parse-regular-recip tokens :allow-null allow-null)
		    (setf tokens remainder)
		    (setf recips (nconc recips new-recips))))))
      recips)))



;; for messages coming in on stdin
(defun get-good-recips-from-string (string &key (pos 0) verbose)
  (let (good-recips)
    (dolist (recip (parse-recip-list string :pos pos))
      (cond
       ((bad-recip-p recip)
	(format t "~A... ~A~%" (recip-orig recip) (recip-errmsg recip)))
       ((include-recip-p recip)
	(format t "~A... Cannot mail directly to :include:s~%" 
		(recip-orig recip)))
       ((error-recip-p recip)
	(format t "~A... Cannot mail directly to :error:s~%" 
		(recip-orig recip)))
       ((file-recip-p recip)
	(format t "~A... Cannot mail directly to files~%" 
		(recip-orig recip)))
       ((error-recip-p recip)
	(format t "~A... Cannot mail directly to programs~%" 
		(recip-orig recip)))
       (t
	(multiple-value-bind (disp msg)
	    (get-recipient-disposition recip)
	  (ecase disp
	    ((:non-local :local-ok)
	     (if verbose
		 (format t "~A... deliverable~%" (recip-orig recip)))
	     (push recip good-recips)) ;; accepted
	    (:error 
	     (format t "~A... ~A~%" (recip-orig recip) msg))
	    (:local-unknown
	     (format t "~A... User unknown~%" (recip-orig recip))))))))
    good-recips))
