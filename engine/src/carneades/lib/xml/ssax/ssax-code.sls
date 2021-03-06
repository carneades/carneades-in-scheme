; Module header is generated automatically
;#cs(module ssax-code mzscheme
;     (require (lib "defmacro.ss"))
;     (require "common.ss")
;     (require "myenv.ss")
;     (require (lib "string.ss" "srfi/13"))
;     (require "util.ss")
;     (require "parse-error.ss")
;     (require "input-parse.ss")
;     (require "look-for-str.ss")
;     (require "char-encoding.ss")

#!r6rs

(library
 
 (carneades lib xml ssax ssax-code)
 
 (export run-test
         make-xml-token
         xml-token?
         xml-token-kind
         xml-token-head
         string-whitespace?
         assq-values
         fold
         ssax:S-chars
         ssax:skip-S
         ssax:ncname-starting-char?
         ssax:read-NCName
         ssax:read-QName
         ssax:Prefix-XML
         ssax:largest-unres-name
         ssax:read-markup-token
         ssax:skip-pi
         ssax:read-pi-body-as-string
         ssax:skip-internal-dtd
         ssax:read-cdata-body
         ssax:read-char-ref
         ssax:predefined-parsed-entities
         ssax:handle-parsed-entity
         make-empty-attlist
         attlist-add
         attlist-null?
         attlist-remove-top
         attlist->alist
         attlist-fold
         ssax:read-attributes 
         ssax:resolve-name
         ssax:uri-string->symbol
         ssax:complete-start-tag
         ssax:read-external-id
         ssax:scan-Misc
         ssax:read-char-data
         ssax:assert-token
         ssax:make-pi-parser
         ssax:make-elem-parser
         ssax:make-parser/positional-args
         ssax:define-labeled-arg-macro
         ssax:make-parser
         ssax:reverse-collect-str
         ssax:reverse-collect-str-drop-ws
         ssax:xml->sxml
         ssax:dtd-xml->sxml
         )
 
 (import (rnrs)
         (carneades lib xml ssax common)
         (carneades lib xml ssax myenv)
         (carneades lib xml ssax util)
         (carneades lib xml ssax parse-error)
         (carneades lib xml ssax input-parse)
         (carneades lib xml ssax look-for-str)
         (carneades lib xml ssax char-encoding)
         (only (carneades lib srfi strings)
               string-index
               string-concatenate/shared
               string-null?
               string-concatenate-reverse/shared
               string-tokenize
               string-trim-both)
         )
 
 (define *debug* #f)
 
 (define-syntax run-test
   (syntax-rules (define) 
     ((run-test "scan-exp" (define vars body)) (define vars (run-test "scan-exp" body)))
     ((run-test "scan-exp" ?body) 
      (letrec-syntax 
          ((scan-exp (syntax-rules (quote quasiquote !) 
                       ((scan-exp (quote ()) (k-head ! . args)) (k-head (quote ()) . args))
                       ((scan-exp (quote (hd . tl)) k) (scan-lit-lst (hd . tl) (do-wrap ! quasiquote k)))
                       ((scan-exp (quasiquote (hd . tl)) k) (scan-lit-lst (hd . tl) (do-wrap ! quasiquote k)))
                       ((scan-exp (quote x) (k-head ! . args)) (k-head (if (string? (quote x))
                                                                           (string->symbol (quote x))
                                                                           (quote x)) . args))
                       ((scan-exp (hd . tl) k) (scan-exp hd (do-tl ! scan-exp tl k)))
                       ((scan-exp x (k-head ! . args)) (k-head x . args))))
           (do-tl (syntax-rules (!)
                    ((do-tl processed-hd fn () (k-head ! . args)) (k-head (processed-hd) . args))
                    ((do-tl processed-hd fn old-tl k) (fn old-tl (do-cons ! processed-hd k)))))
           (do-cons (syntax-rules (!)
                      ((do-cons processed-tl processed-hd (k-head ! . args)) (k-head (processed-hd . processed-tl) . args))))
           (do-wrap (syntax-rules (!)
                      ((do-wrap val fn (k-head ! . args)) (k-head (fn val) . args))))
           (do-finish (syntax-rules ()
                        ((do-finish new-body) new-body)))
           (scan-lit-lst (syntax-rules (quote unquote unquote-splicing !)
                           ((scan-lit-lst (quote ()) (k-head ! . args)) (k-head (quote ()) . args))
                           ((scan-lit-lst (quote (hd . tl)) k) (do-tl quote scan-lit-lst ((hd . tl)) k))
                           ((scan-lit-lst (unquote x) k) (scan-exp x (do-wrap ! unquote k)))
                           ((scan-lit-lst (unquote-splicing x) k) (scan-exp x (do-wrap ! unquote-splicing k)))
                           ((scan-lit-lst (quote x) (k-head ! . args)) (k-head (unquote (if (string? (quote x))
                                                                                            (string->symbol (quote x))
                                                                                            (quote x))) . args))
                           ((scan-lit-lst (hd . tl) k) (scan-lit-lst hd (do-tl ! scan-lit-lst tl k)))
                           ((scan-lit-lst x (k-head ! . args)) (k-head x . args))))
           ) 
        (scan-exp ?body (do-finish !))))
     ((run-test body ...) (begin (run-test "scan-exp" body) ...))))
 
 (define (make-xml-token kind head) (cons kind head))
 
 (define xml-token? pair?)
 
 (define-syntax xml-token-kind (syntax-rules () ((xml-token-kind token) (car token))))
 
 (define-syntax xml-token-head (syntax-rules () ((xml-token-head token) (cdr token))))
 
 (define (string-whitespace? str)
   (let ((len (string-length str)))
     (cond 
       ((zero? len) #t) 
       ((= 1 len) (char-whitespace? (string-ref str 0)))
       ((= 2 len) (and (char-whitespace? (string-ref str 0)) (char-whitespace? (string-ref str 1))))
       (else (let loop ((i 0)) (or (>= i len) (and (char-whitespace? (string-ref str i)) (loop (inc i)))))))))
 
 (define (assq-values val alist)
   (let loop ((alist alist) (scanned (quote ())))
     (cond 
       ((null? alist) (values #f scanned))
       ((equal? val (caar alist)) (values (car alist) (append scanned (cdr alist))))
       (else (loop (cdr alist) (cons (car alist) scanned))))))
 
 ; already in r6rs
 #;(define (fold-right kons knil lis1)
     (let recur ((lis lis1)) (if (null? lis)
                                 knil 
                                 (let ((head (car lis))) (kons head (recur (cdr lis)))))))
 
 (define (fold kons knil lis1)
   (let lp ((lis lis1) (ans knil)) (if (null? lis)
                                       ans
                                       (lp (cdr lis) (kons (car lis) ans)))))
 
 (define ssax:S-chars (map ascii->char (quote (32 10 9 13))))
 
 (define (ssax:skip-S port) (skip-while ssax:S-chars port))
 
 (define (ssax:ncname-starting-char? a-char)
   (and (char? a-char) (or (char-alphabetic? a-char) (char=? #\_ a-char))))
 
 (define (ssax:read-NCName port)
   (let ((first-char (peek-char port)))
     (or (ssax:ncname-starting-char? first-char)
         (parser-error port "XMLNS [4] for '" first-char "'")))
   (string->symbol (next-token-of (lambda (c)
                                    (cond ((eof-object? c) #f)
                                          ((char-alphabetic? c) c)
                                          ((string-index "0123456789.-_" c) c)
                                          (else #f)))
                                  port)))
 
 (define (ssax:read-QName port)
   (let ((prefix-or-localpart (ssax:read-NCName port)))
     (case (peek-char port)
       ((#\:) (read-char port) (cons prefix-or-localpart (ssax:read-NCName port)))
       (else prefix-or-localpart))))
 
 (define ssax:Prefix-XML (string->symbol "xml"))
 
 (define name-compare 
   (letrec ((symbol-compare 
             (lambda (symb1 symb2)
               (cond ((eq? symb1 symb2) (quote =))
                     ((string<? (symbol->string symb1) (symbol->string symb2)) (quote <))
                     (else (quote >))))))
     (lambda (name1 name2)
       (cond 
         ((symbol? name1) (if (symbol? name2) (symbol-compare name1 name2) (quote <)))
         ((symbol? name2) (quote >))
         ((eq? name2 ssax:largest-unres-name) (quote <))
         ((eq? name1 ssax:largest-unres-name) (quote >))
         ((eq? (car name1) (car name2)) (symbol-compare (cdr name1) (cdr name2)))
         (else (symbol-compare (car name1) (car name2)))))))
 
 (define ssax:largest-unres-name 
   (cons (string->symbol "#LARGEST-SYMBOL") (string->symbol "#LARGEST-SYMBOL")))
 
 (define ssax:read-markup-token 
   (let () 
     (define (skip-comment port)
       (assert-curr-char (quote (#\-)) "XML [15], second dash" port)
       (if (not (find-string-from-port? "-->" port)) (parser-error port "XML [15], no -->"))
       (make-xml-token (quote COMMENT) #f))
     (define (read-cdata port)
       (assert (string=? "CDATA[" (get-string-n port 6)))
       (make-xml-token (quote CDSECT) #f))
     (lambda (port)
       (assert-curr-char (quote (#\<)) "start of the token" port)
       (case (peek-char port)
         ((#\/) (read-char port) (let ((result (make-xml-token (quote END) (ssax:read-QName port))))
                                   (ssax:skip-S port)
                                   (assert-curr-char (quote (#\>)) "XML [42]" port)
                                   result))
         ((#\?) (read-char port) (make-xml-token (quote PI) (ssax:read-NCName port)))
         ((#\!) (case (peek-next-char port) 
                  ((#\-) (read-char port) (skip-comment port))
                  ((#\[) (read-char port) (read-cdata port))
                  (else (make-xml-token (quote DECL) (ssax:read-NCName port)))))
         (else (make-xml-token (quote START) (ssax:read-QName port)))))))
 
 (define (ssax:skip-pi port)
   (if (not (find-string-from-port? "?>" port))
       (parser-error port "Failed to find ?> terminating the PI")))
 
 (define (ssax:read-pi-body-as-string port)
   (ssax:skip-S port)
   (string-concatenate/shared 
    (let loop () 
      (let ((pi-fragment (next-token (quote ()) (quote (#\?)) "reading PI content" port)))
        (if (eqv? #\> (peek-next-char port))
            (begin 
              (read-char port)
              (cons pi-fragment (quote ())))
            (cons* pi-fragment "?" (loop)))))))
 
 (define (ssax:skip-internal-dtd port)
   (if (not (find-string-from-port? "]>" port))
       (parser-error port "Failed to find ]> terminating the internal DTD subset")))
 
 (define ssax:read-cdata-body 
   (let ((cdata-delimiters (list char-return #\newline #\] #\&)))
     (lambda (port str-handler seed)
       (let loop ((seed seed))
         (let ((fragment (next-token (quote ()) cdata-delimiters "reading CDATA" port)))
           (case (read-char port)
             ((#\newline) (loop (str-handler fragment nl seed)))
             ((#\]) (if (not (eqv? (peek-char port) #\]))
                        (loop (str-handler fragment "]" seed))
                        (let check-after-second-braket 
                          ((seed (if (string-null? fragment) seed (str-handler fragment "" seed))))
                          (case (peek-next-char port)
                            ((#\>) (read-char port) seed)
                            ((#\]) (check-after-second-braket (str-handler "]" "" seed)))
                            (else (loop (str-handler "]]" "" seed)))))))
             ((#\&) (let ((ent-ref (next-token-of (lambda (c) (and (not (eof-object? c)) (char-alphabetic? c) c)) port)))
                      (cond ((and (string=? "gt" ent-ref) 
                                  (eqv? (peek-char port) #\;))
                             (read-char port)
                             (loop (str-handler fragment ">" seed)))
                            (else (loop (str-handler ent-ref "" (str-handler fragment "&" seed)))))))
             (else (if (eqv? (peek-char port) #\newline)
                       (read-char port))
                   (loop (str-handler fragment nl seed)))))))))
 
 (define (ssax:read-char-ref port)
   (let* ((base (cond ((eqv? (peek-char port) #\x) (read-char port) 16) (else 10)))
          (name (next-token (quote ()) (quote (#\;)) "XML [66]" port))
          (char-code (string->number name base)))
     (read-char port)
     (if (integer? char-code)
         (ucscode->char char-code)
         (parser-error port "[wf-Legalchar] broken for '" name "'"))))
 
 (define ssax:predefined-parsed-entities
   (quasiquote (((unquote (string->symbol "amp")) . "&")
                ((unquote (string->symbol "lt")) . "<")
                ((unquote (string->symbol "gt")) . ">")
                ((unquote (string->symbol "apos")) . "'")
                ((unquote (string->symbol "quot")) . "\""))))
 
 (define (ssax:handle-parsed-entity port name entities content-handler str-handler seed)
   (cond ((assq name entities)
          => (lambda (decl-entity)
               (let ((ent-body (cdr decl-entity))
                     (new-entities (cons (cons name #f) entities)))
                 (cond (
                        (string? ent-body)
                        (call-with-input-string ent-body 
                                                (lambda (port) 
                                                  (content-handler port new-entities seed))))
                       ((procedure? ent-body) (let ((port (ent-body)))
                                                (let ((result 
                                                       (content-handler port new-entities seed)))
                                                  (close-input-port port)
                                                  result)))
                       (else (parser-error port "[norecursion] broken for " name))))))
         ((assq name ssax:predefined-parsed-entities)
          => (lambda (decl-entity) (str-handler (cdr decl-entity) "" seed)))
         (else (parser-error port "[wf-entdeclared] broken for " name))))
 
 (define (make-empty-attlist) (quote ()))
 
 (define (attlist-add attlist name-value)
   (if (null? attlist)
       (cons name-value attlist)
       (case (name-compare (car name-value) (caar attlist))
         ((=) #f)
         ((<) (cons name-value attlist))
         (else (cons (car attlist) (attlist-add (cdr attlist) name-value))))))
 
 (define attlist-null? null?)
 
 (define (attlist-remove-top attlist) (values (car attlist) (cdr attlist)))
 
 (define (attlist->alist attlist) attlist)
 
 (define attlist-fold fold)
 
 (define ssax:read-attributes 
   (let ((value-delimeters (append ssax:S-chars (quote (#\< #\&)))))
     (define (read-attrib-value delimiter port entities prev-fragments)
       (let* ((new-fragments (cons (next-token (quote ()) (cons delimiter value-delimeters) "XML [10]" port) prev-fragments))
              (cterm (read-char port)))
         (cond ((or (eof-object? cterm)
                    (eqv? cterm delimiter))
                new-fragments)
               ((eqv? cterm char-return) (if (eqv? (peek-char port) #\newline)
                                             (read-char port))
                                         (read-attrib-value delimiter port entities (cons " " new-fragments)))
               ((memv cterm ssax:S-chars) (read-attrib-value delimiter port entities (cons " " new-fragments)))
               ((eqv? cterm #\&) (cond ((eqv? (peek-char port) #\#)
                                        (read-char port)
                                        (read-attrib-value delimiter
                                                           port
                                                           entities
                                                           (cons (string (ssax:read-char-ref port)) new-fragments)))
                                       (else (read-attrib-value delimiter
                                                                port
                                                                entities
                                                                (read-named-entity port entities new-fragments)))))
               (else (parser-error port "[CleanAttrVals] broken")))))
     (define (read-named-entity port entities fragments)
       (let ((name (ssax:read-NCName port)))
         (assert-curr-char (quote (#\;)) "XML [68]" port)
         (ssax:handle-parsed-entity port
                                    name
                                    entities
                                    (lambda (port entities fragments)
                                      (read-attrib-value (quote *eof*) port entities fragments))
                                    (lambda (str1 str2 fragments)
                                      (if (equal? "" str2) 
                                          (cons str1 fragments)
                                          (cons* str2 str1 fragments)))
                                    fragments)))
     (lambda (port entities)
       (let loop ((attr-list (make-empty-attlist)))
         (if (not (ssax:ncname-starting-char? (ssax:skip-S port)))
             attr-list
             (let ((name (ssax:read-QName port)))
               (ssax:skip-S port)
               (assert-curr-char (quote (#\=)) "XML [25]" port)
               (ssax:skip-S port)
               (let ((delimiter (assert-curr-char (quote (#\' #\")) "XML [10]" port)))
                 (loop (or (attlist-add attr-list
                                        (cons name 
                                              (string-concatenate-reverse/shared
                                               (read-attrib-value delimiter port entities (quote ())))))
                           (parser-error port "[uniqattspec] broken for " name))))))))))
 
 (define (ssax:resolve-name port unres-name namespaces apply-default-ns?)
   (cond ((pair? unres-name) (cons (cond ((assq (car unres-name) namespaces) => cadr)
                                         ((eq? (car unres-name) ssax:Prefix-XML) ssax:Prefix-XML)
                                         (else (parser-error port "[nsc-NSDeclared] broken; prefix " (car unres-name))))
                                   (cdr unres-name)))
         (apply-default-ns? (let ((default-ns (assq (quote *DEFAULT*) namespaces)))
                              (if (and default-ns (cadr default-ns))
                                  (cons (cadr default-ns) unres-name)
                                  unres-name)))
         (else unres-name)))
 
 (define (ssax:uri-string->symbol uri-str) 
   (string->symbol uri-str))
 
 (define ssax:complete-start-tag
   (let ((xmlns (string->symbol "xmlns"))
         (largest-dummy-decl-attr (list ssax:largest-unres-name #f #f #f)))
     (define (validate-attrs port attlist decl-attrs)
       (define (add-default-decl decl-attr result)
         (let*-values (((attr-name content-type use-type default-value) (apply values decl-attr)))
           (and (eq? use-type (quote REQUIRED))
                (parser-error port "[RequiredAttr] broken for" attr-name))
           (if default-value 
               (cons (cons attr-name default-value) result)
               result)))
       (let loop ((attlist attlist)
                  (decl-attrs decl-attrs)
                  (result (quote ())))
         (if (attlist-null? attlist)
             (attlist-fold add-default-decl result decl-attrs)
             (let*-values (((attr attr-others) (attlist-remove-top attlist))
                           ((decl-attr other-decls) (if (attlist-null? decl-attrs)
                                                        (values largest-dummy-decl-attr decl-attrs)
                                                        (attlist-remove-top decl-attrs))))
               (case (name-compare (car attr) (car decl-attr))
                 ((<) (if (or (eq? xmlns (car attr))
                              (and (pair? (car attr))
                                   (eq? xmlns (caar attr))))
                          (loop attr-others decl-attrs (cons attr result))
                          (parser-error port "[ValueType] broken for " attr)))
                 ((>) (loop attlist other-decls (add-default-decl decl-attr result)))
                 (else (let*-values (((attr-name content-type use-type default-value) (apply values decl-attr)))
                         (cond ((eq? use-type (quote FIXED))
                                (or (equal? (cdr attr) default-value)
                                    (parser-error port "[FixedAttr] broken for " attr-name)))
                               ((eq? content-type (quote CDATA)) #t)
                               ((pair? content-type) (or (member (cdr attr) content-type)
                                                         (parser-error port "[enum] broken for " attr-name "=" (cdr attr))))
                               (else (ssax:warn port "declared content type " content-type " not verified yet")))
                         (loop attr-others other-decls (cons attr result)))))))))
     (define (add-ns port prefix uri-str namespaces)
       (and (equal? "" uri-str)
            (parser-error port "[dt-NSName] broken for " prefix))
       (let ((uri-symbol (ssax:uri-string->symbol uri-str)))
         (let loop ((nss namespaces))
           (cond ((null? nss) (cons (cons* prefix uri-symbol uri-symbol) namespaces))
                 ((eq? uri-symbol (cddar nss)) (cons (cons* prefix (cadar nss) uri-symbol) namespaces))
                 (else (loop (cdr nss)))))))
     (define (adjust-namespace-decl port attrs namespaces)
       (let loop ((attrs attrs)
                  (proper-attrs (quote ()))
                  (namespaces namespaces))
         (cond ((null? attrs) (values proper-attrs namespaces))
               ((eq? xmlns (caar attrs))
                (loop (cdr attrs) proper-attrs (if (equal? "" (cdar attrs))
                                                   (cons (cons* (quote *DEFAULT*) #f #f) namespaces)
                                                   (add-ns port (quote *DEFAULT*) (cdar attrs) namespaces))))
               ((and (pair? (caar attrs))
                     (eq? xmlns (caaar attrs)))
                (loop (cdr attrs) proper-attrs (add-ns port (cdaar attrs) (cdar attrs) namespaces)))
               (else (loop (cdr attrs) (cons (car attrs) proper-attrs) namespaces)))))
     (lambda (tag-head port elems entities namespaces)
       (let*-values (((attlist) (ssax:read-attributes port entities))
                     ((empty-el-tag?) (begin
                                        (ssax:skip-S port)
                                        (and (eqv? #\/ (assert-curr-char (quote (#\> #\/)) "XML [40], XML [44], no '>'" port))
                                             (assert-curr-char (quote (#\>)) "XML [44], no '>'" port))))
                     ((elem-content decl-attrs)
                      (if elems 
                          (cond ((assoc tag-head elems)
                                 => (lambda (decl-elem)
                                      (values (if empty-el-tag?
                                                  (quote EMPTY-TAG)
                                                  (cadr decl-elem))
                                              (caddr decl-elem))))
                                (else (parser-error port "[elementvalid] broken, no decl for " tag-head)))
                          (values (if empty-el-tag? (quote EMPTY-TAG) (quote ANY)) #f)))
                     ((merged-attrs) (if decl-attrs (validate-attrs port attlist decl-attrs) (attlist->alist attlist)))
                     ((proper-attrs namespaces) (adjust-namespace-decl port merged-attrs namespaces)))
         (values (ssax:resolve-name port tag-head namespaces #t)
                 (fold-right (lambda (name-value attlist)
                               (or (attlist-add attlist (cons (ssax:resolve-name port
                                                                                 (car name-value)
                                                                                 namespaces
                                                                                 #f)
                                                              (cdr name-value)))
                                   (parser-error port "[uniqattspec] after NS expansion broken for " name-value)))
                             (make-empty-attlist) proper-attrs)
                 namespaces elem-content)))))
 
 (define (ssax:read-external-id port)
   (let ((discriminator (ssax:read-NCName port)))
     (assert-curr-char ssax:S-chars "space after SYSTEM or PUBLIC" port)
     (ssax:skip-S port)
     (let ((delimiter (assert-curr-char (quote (#\' #\")) "XML [11], XML [12]" port)))
       (cond ((eq? discriminator (string->symbol "SYSTEM")) 
              (let ((result
                     (next-token (quote ()) (list delimiter) "XML [11]" port)))
                (read-char port)
                result))
             ((eq? discriminator (string->symbol "PUBLIC")) 
              (skip-until (list delimiter) port)
              (assert-curr-char ssax:S-chars "space after PubidLiteral" port)
              (ssax:skip-S port)
              (let* ((delimiter (assert-curr-char (quote (#\' #\")) "XML [11]" port))
                     (systemid (next-token (quote ()) (list delimiter) "XML [11]" port)))
                (read-char port)
                systemid))
             (else (parser-error port "XML [75], " discriminator " rather than SYSTEM or PUBLIC"))))))
 
 (define (ssax:scan-Misc port)
   (let loop ((c (ssax:skip-S port)))
     (cond ((eof-object? c) c)
           ((not (char=? c #\<)) (parser-error port "XML [22], char '" c "' unexpected"))
           (else (let ((token (ssax:read-markup-token port)))
                   (case (xml-token-kind token) 
                     ((COMMENT) (loop (ssax:skip-S port)))
                     ((PI DECL START) token)
                     (else (parser-error port "XML [22], unexpected token of kind " (xml-token-kind token)))))))))
 
 (define ssax:read-char-data
   (let ((terminators-usual (list #\< #\& char-return))
         (terminators-usual-eof (list #\< (quote *eof*) #\& char-return))
         (handle-fragment (lambda (fragment str-handler seed)
                            (if (string-null? fragment)
                                seed
                                (str-handler fragment "" seed)))))
     (lambda (port expect-eof? str-handler seed)
       (if (eqv? #\< (peek-char port))
           (let ((token (ssax:read-markup-token port)))
             (case (xml-token-kind token)
               ((START END) (values seed token))
               ((CDSECT) (let ((seed (ssax:read-cdata-body port str-handler seed)))
                           (ssax:read-char-data port expect-eof? str-handler seed)))
               ((COMMENT) (ssax:read-char-data port expect-eof? str-handler seed))
               (else (values seed token))))
           (let ((char-data-terminators (if expect-eof? terminators-usual-eof terminators-usual)))
             (let loop ((seed seed))
               (let* ((fragment (next-token (quote ()) char-data-terminators "reading char data" port))
                      (term-char (peek-char port)))
                 (if (eof-object? term-char)
                     (values (handle-fragment fragment str-handler seed) term-char)
                     (case term-char 
                       ((#\<) (let ((token (ssax:read-markup-token port)))
                                (case (xml-token-kind token) 
                                  ((CDSECT) 
                                   (loop (ssax:read-cdata-body port str-handler (handle-fragment fragment str-handler seed))))
                                  ((COMMENT) 
                                   (loop (handle-fragment fragment str-handler seed)))
                                  (else 
                                   (values (handle-fragment fragment str-handler seed) token)))))
                       ((#\&) (case (peek-next-char port)
                                ((#\#) (read-char port)
                                       (loop (str-handler fragment (string (ssax:read-char-ref port)) seed)))
                                (else (let ((name (ssax:read-NCName port)))
                                        (assert-curr-char (quote (#\;)) "XML [68]" port)
                                        (values (handle-fragment fragment str-handler seed)
                                                (make-xml-token (quote ENTITY-REF) name))))))
                       (else (if (eqv? (peek-next-char port) #\newline)
                                 (read-char port))
                             (loop (str-handler fragment (string #\newline) seed))))))))))))
 
 (define (ssax:assert-token token kind gi error-cont)
   (or (and (xml-token? token)
            (eq? kind (xml-token-kind token))
            (equal? gi (xml-token-head token)))
       (error-cont token kind gi)))
 
 (define-syntax ssax:make-pi-parser
   (syntax-rules ()
     ((ssax:make-pi-parser orig-handlers)
      (letrec-syntax 
          ((loop (syntax-rules (*DEFAULT*)
                   ((loop () #f accum port target seed)
                    (make-case ((else (ssax:warn port "Skipping PI: " target nl) (ssax:skip-pi port) seed) . accum)
                               ()
                               target))
                   ((loop () default accum port target seed)
                    (make-case ((else (default port target seed)) . accum) 
                               () 
                               target))
                   ((loop ((*DEFAULT* . default) . handlers) old-def accum port target seed)
                    (loop handlers default accum port target seed))
                   ((loop ((tag . handler) . handlers) default accum port target seed)
                    (loop handlers default (((tag) (handler port target seed)) . accum) port target seed))))
           (make-case (syntax-rules ()
                        ((make-case () clauses target) (case target . clauses))
                        ((make-case (clause . clauses) accum target) (make-case clauses (clause . accum) target)))))
        (lambda (port target seed) (loop orig-handlers #f () port target seed))))))
 
 (define-syntax ssax:make-elem-parser 
   (syntax-rules ()
     ((ssax:make-elem-parser my-new-level-seed my-finish-element my-char-data-handler my-pi-handlers)
      (lambda (start-tag-head port elems entities namespaces preserve-ws? seed)
        (define xml-space-gi (cons ssax:Prefix-XML (string->symbol "space")))
        (let handle-start-tag ((start-tag-head start-tag-head)
                               (port port)
                               (entities entities)
                               (namespaces namespaces)
                               (preserve-ws? preserve-ws?)
                               (parent-seed seed))
          (let*-values (((elem-gi attributes namespaces expected-content)
                         (ssax:complete-start-tag start-tag-head port elems entities namespaces))
                        ((seed) (my-new-level-seed elem-gi attributes namespaces expected-content parent-seed)))
            (case expected-content 
              ((EMPTY-TAG) (my-finish-element elem-gi attributes namespaces parent-seed seed))
              ((EMPTY) (ssax:assert-token
                        (and (eqv? #\< (ssax:skip-S port))
                             (ssax:read-markup-token port))
                        (quote END)
                        start-tag-head
                        (lambda (token exp-kind exp-head)
                          (parser-error port
                                        "[elementvalid] broken for "
                                        token 
                                        " while expecting "
                                        exp-kind exp-head)))
                       (my-finish-element elem-gi attributes namespaces parent-seed seed))
              (else (let ((preserve-ws? (cond ((assoc xml-space-gi attributes)
                                               => (lambda (name-value)
                                                    (equal? "preserve" (cdr name-value))))
                                              (else preserve-ws?))))
                      (let loop ((port port)
                                 (entities entities)
                                 (expect-eof? #f)
                                 (seed seed))
                        (let*-values (((seed term-token) (ssax:read-char-data port expect-eof? my-char-data-handler seed)))
                          (if (eof-object? term-token)
                              seed
                              (case (xml-token-kind term-token)
                                ((END) 
                                 (ssax:assert-token term-token
                                                    (quote END)
                                                    start-tag-head
                                                    (lambda (token exp-kind exp-head)
                                                      (parser-error port 
                                                                    "[GIMatch] broken for "
                                                                    term-token
                                                                    " while expecting "
                                                                    exp-kind exp-head)))
                                 (my-finish-element elem-gi attributes namespaces parent-seed seed))
                                ((PI) (let ((seed ((ssax:make-pi-parser my-pi-handlers) port (xml-token-head term-token) seed)))
                                        (loop port entities expect-eof? seed)))
                                ((ENTITY-REF) (let ((seed (ssax:handle-parsed-entity
                                                           port
                                                           (xml-token-head term-token)
                                                           entities
                                                           (lambda (port entities seed)
                                                             (loop port entities #t seed)) my-char-data-handler seed)))
                                                (loop port entities expect-eof? seed)))
                                ((START) (if (eq? expected-content (quote PCDATA))
                                             (parser-error port
                                                           "[elementvalid] broken for "
                                                           elem-gi
                                                           " with char content only; unexpected token "
                                                           term-token))
                                         (let ((seed (handle-start-tag 
                                                      (xml-token-head term-token)
                                                      port
                                                      entities
                                                      namespaces
                                                      preserve-ws?
                                                      seed)))
                                           (loop port entities expect-eof? seed)))
                                (else (parser-error port "XML [43] broken for " term-token)))))))))))))))
 
 (define-syntax ssax:make-parser/positional-args
   (syntax-rules ()
     ((ssax:make-parser/positional-args *handler-DOCTYPE
                                        *handler-UNDECL-ROOT
                                        *handler-DECL-ROOT
                                        *handler-NEW-LEVEL-SEED
                                        *handler-FINISH-ELEMENT
                                        *handler-CHAR-DATA-HANDLER
                                        *handler-PI)
      (lambda (port seed)
        (define (handle-decl port token-head seed)
          (or (eq? (string->symbol "DOCTYPE") token-head)
              (parser-error port "XML [22], expected DOCTYPE declaration, found " token-head))
          (assert-curr-char ssax:S-chars "XML [28], space after DOCTYPE" port)
          (ssax:skip-S port)
          (let*-values (((docname) (ssax:read-QName port))
                        ((systemid) (and (ssax:ncname-starting-char? (ssax:skip-S port)) (ssax:read-external-id port)))
                        ((internal-subset?) (begin 
                                              (ssax:skip-S port)
                                              (eqv? #\[ (assert-curr-char (quote (#\> #\[)) "XML [28], end-of-DOCTYPE" port))))
                        ((elems entities namespaces seed) (*handler-DOCTYPE port docname systemid internal-subset? seed)))
            (scan-for-significant-prolog-token-2 port elems entities namespaces seed)))
        (define (scan-for-significant-prolog-token-1 port seed)
          (let ((token (ssax:scan-Misc port)))
            (if (eof-object? token)
                (parser-error port "XML [22], unexpected EOF")
                (case (xml-token-kind token)
                  ((PI) (let ((seed ((ssax:make-pi-parser *handler-PI) port (xml-token-head token) seed)))
                          (scan-for-significant-prolog-token-1 port seed)))
                  ((DECL) (handle-decl port (xml-token-head token) seed))
                  ((START) (let*-values (((elems entities namespaces seed) (*handler-UNDECL-ROOT (xml-token-head token) seed)))
                             (element-parser (xml-token-head token) port elems entities namespaces #f seed)))
                  (else (parser-error port "XML [22], unexpected markup " token))))))
        (define (scan-for-significant-prolog-token-2 port elems entities namespaces seed)
          (let ((token (ssax:scan-Misc port)))
            (if (eof-object? token)
                (parser-error port "XML [22], unexpected EOF")
                (case (xml-token-kind token) 
                  ((PI) (let ((seed ((ssax:make-pi-parser *handler-PI) port (xml-token-head token) seed)))
                          (scan-for-significant-prolog-token-2 port elems entities namespaces seed)))
                  ((START) (element-parser (xml-token-head token)
                                           port
                                           elems
                                           entities
                                           namespaces
                                           #f
                                           (*handler-DECL-ROOT (xml-token-head token) seed)))
                  (else (parser-error port "XML [22], unexpected markup " token))))))
        (define element-parser
          (ssax:make-elem-parser *handler-NEW-LEVEL-SEED
                                 *handler-FINISH-ELEMENT
                                 *handler-CHAR-DATA-HANDLER
                                 *handler-PI))
        (scan-for-significant-prolog-token-1 port seed)))))
 
 (define-syntax ssax:define-labeled-arg-macro
   (syntax-rules ()
     ((ssax:define-labeled-arg-macro labeled-arg-macro-name (positional-macro-name (arg-name . arg-def) ...))
      (define-syntax labeled-arg-macro-name
        (syntax-rules () 
          ((labeled-arg-macro-name . kw-val-pairs)
           (letrec-syntax 
               ((find (syntax-rules (arg-name ...)
                        ((find k-args (arg-name . default) arg-name val . others) (next val . k-args))
                        ...
                        ((find k-args key arg-no-match-name val . others) (find k-args key . others))
                        ((find k-args (arg-name default)) (next default . k-args))
                        ...))
                (next (syntax-rules ()
                        ((next val vals key . keys) (find ((val . vals) . keys) key . kw-val-pairs))
                        ((next val vals) (rev-apply (val) vals))))
                (rev-apply (syntax-rules ()
                             ((rev-apply form (x . xs)) (rev-apply (x . form) xs))
                             ((rev-apply form ()) form))))
             (next positional-macro-name () (arg-name . arg-def) ...))))))))
 
 (ssax:define-labeled-arg-macro 
  ssax:make-parser
  (ssax:make-parser/positional-args 
   (DOCTYPE (lambda (port docname systemid internal-subset? seed)
              (when internal-subset? 
                (ssax:warn port "Internal DTD subset is not currently handled ")
                
                (ssax:skip-internal-dtd port))
              (ssax:warn port "DOCTYPE DECL " docname " " systemid " found and skipped")
              (values #f (quote ()) (quote ()) seed)))
   (UNDECL-ROOT (lambda (elem-gi seed)
                  (values #f (quote ()) (quote ()) seed)))
   (DECL-ROOT (lambda (elem-gi seed) seed))
   (NEW-LEVEL-SEED)
   (FINISH-ELEMENT)
   (CHAR-DATA-HANDLER)
   (PI ())))
 
 (define (ssax:reverse-collect-str fragments)
   (cond ((null? fragments) (quote ()))
         ((null? (cdr fragments)) fragments)
         (else (let loop ((fragments fragments) (result (quote ())) (strs (quote ())))
                 (cond ((null? fragments) (if (null? strs)
                                              result
                                              (cons (string-concatenate/shared strs) result))) 
                       ((string? (car fragments)) (loop (cdr fragments) result (cons (car fragments) strs)))
                       (else (loop (cdr fragments) (cons (car fragments)
                                                         (if (null? strs)
                                                             result
                                                             (cons (string-concatenate/shared strs) result)))
                                   (quote ()))))))))
 
 (define (ssax:reverse-collect-str-drop-ws fragments)
   (cond ((null? fragments) (quote ()))
         ((null? (cdr fragments)) (if (and (string? (car fragments))
                                           (string-whitespace? (car fragments)))
                                      (quote ())
                                      fragments))
         (else (let loop ((fragments fragments) (result (quote ())) (strs (quote ())) (all-whitespace? #t))
                 (cond ((null? fragments) (if all-whitespace?
                                              result
                                              (cons (string-concatenate/shared strs) result)))
                       ((string? (car fragments)) (loop (cdr fragments)
                                                        result
                                                        (cons (car fragments) strs)
                                                        (and all-whitespace?
                                                             (string-whitespace? (car fragments)))))
                       (else (loop (cdr fragments) 
                                   (cons (car fragments) (if all-whitespace?
                                                             result
                                                             (cons (string-concatenate/shared strs) result)))
                                   (quote ()) #t)))))))
 
 (define (ssax:xml->sxml port namespace-prefix-assig)
   (letrec ((namespaces (map (lambda (el)
                               (cons* #f (car el) (ssax:uri-string->symbol (cdr el))))
                             namespace-prefix-assig))
            (RES-NAME->SXML (lambda (res-name)
                              (string->symbol 
                               (string-append 
                                (symbol->string (car res-name))
                                ":"
                                (symbol->string (cdr res-name)))))))
     (let ((result (reverse ((ssax:make-parser 
                              NEW-LEVEL-SEED
                              (lambda (elem-gi attributes namespaces expected-content seed) (quote ()))
                              FINISH-ELEMENT
                              (lambda (elem-gi attributes namespaces parent-seed seed)
                                (let ((seed (ssax:reverse-collect-str-drop-ws seed))
                                      (attrs (attlist-fold (lambda (attr accum)
                                                             (cons (list 
                                                                    (if (symbol? (car attr))
                                                                        (car attr)
                                                                        (RES-NAME->SXML (car attr)))
                                                                    (cdr attr))
                                                                   accum))
                                                           (quote ())
                                                           attributes)))
                                  (cons (cons (if (symbol? elem-gi)
                                                  elem-gi
                                                  (RES-NAME->SXML elem-gi))
                                              (if (null? attrs)
                                                  seed 
                                                  (cons (cons '^ attrs) seed)))
                                        parent-seed)))
                              CHAR-DATA-HANDLER
                              (lambda (string1 string2 seed)
                                (if (string-null? string2)
                                    (cons string1 seed)
                                    (cons* string2 string1 seed)))
                              DOCTYPE
                              (lambda (port docname systemid internal-subset? seed)
                                (when internal-subset?
                                  (ssax:warn port "Internal DTD subset is not currently handled ")
                                  (ssax:skip-internal-dtd port))
                                (ssax:warn port "DOCTYPE DECL " docname " " systemid " found and skipped")
                                (values #f (quote ()) namespaces seed))
                              UNDECL-ROOT
                              (lambda (elem-gi seed) (values #f (quote ()) namespaces seed))
                              PI
                              ((*DEFAULT* lambda (port pi-tag seed)
                                          (cons (list (quote *PI*) pi-tag (ssax:read-pi-body-as-string port)) seed))))
                             port (quote ())))))
       (cons (quote *TOP*) (if (null? namespace-prefix-assig)
                               result
                               (cons (list '^
                                           (cons (quote *NAMESPACES*)
                                                 (map (lambda (ns)
                                                        (list (car ns) (cdr ns)))
                                                      namespace-prefix-assig)))
                                     result))))))
 
 (define (ssax:dtd-xml->sxml port namespace-prefix-assig)
   (letrec ((namespaces (map (lambda (el)
                               (cons* #f (car el) (ssax:uri-string->symbol (cdr el))))
                             namespace-prefix-assig))
            (RES-NAME->SXML (lambda (res-name)
                              (string->symbol 
                               (string-append 
                                (symbol->string (car res-name))
                                ":"
                                (symbol->string (cdr res-name)))))))
     (let ((result (reverse ((ssax:make-parser 
                              NEW-LEVEL-SEED
                              (lambda (elem-gi attributes namespaces expected-content seed) (quote ()))
                              FINISH-ELEMENT
                              (lambda (elem-gi attributes namespaces parent-seed seed)
                                (let ((seed (ssax:reverse-collect-str-drop-ws seed))
                                      (attrs (attlist-fold (lambda (attr accum)
                                                             (cons (list 
                                                                    (if (symbol? (car attr))
                                                                        (car attr)
                                                                        (RES-NAME->SXML (car attr)))
                                                                    (cdr attr))
                                                                   accum))
                                                           (quote ())
                                                           attributes)))
                                  (cons (cons (if (symbol? elem-gi)
                                                  elem-gi
                                                  (RES-NAME->SXML elem-gi))
                                              (if (null? attrs)
                                                  seed 
                                                  (cons (cons '^ attrs) seed)))
                                        parent-seed)))
                              CHAR-DATA-HANDLER
                              (lambda (string1 string2 seed)
                                (if (string-null? string2)
                                    (cons string1 seed)
                                    (cons* string2 string1 seed)))
                              DOCTYPE
                              (lambda (port docname systemid internal-subset? seed)
                                (doctype-handler port docname systemid internal-subset? seed namespaces))
                              UNDECL-ROOT
                              (lambda (elem-gi seed) (values #f (quote ()) namespaces seed))
                              PI
                              ((*DEFAULT* lambda (port pi-tag seed)
                                          (cons (list (quote *PI*) pi-tag (ssax:read-pi-body-as-string port)) seed))))
                             port (quote ())))))
       (cons (quote *TOP*) (if (null? namespace-prefix-assig)
                               result
                               (cons (list '^
                                           (cons (quote *NAMESPACES*)
                                                 (map (lambda (ns)
                                                        (list (car ns) (cdr ns)))
                                                      namespace-prefix-assig)))
                                     result))))))
 
 (define (extract-entities port entities)
   (let* ((l (get-line port))
          (line (if (string? l)
                    (string-tokenize l)
                    l)))
     (if *debug*
         (begin (display "extract-entities: ")
                (write line)
                (newline)))
     (if (string=? (string-trim-both l) "]>")                         
         entities
         (if (and (list? line)
                  (>= (length line) 3))
             (let ((ent (car line))
                   (name (string->symbol (cadr line)))
                   (uri (string-trim-both (caddr line) #\")))
               (if *debug*
                   (begin (display "ent: ")
                          (write ent)
                          (newline)
                          (display "name: ")
                          (write name)
                          (newline)
                          (display "uri: ")
                          (write uri)
                          (newline)))
               (if (string=? ent "<!ENTITY")
                   (extract-entities port (append entities (list (cons name uri))))
                   (extract-entities port entities)))
                                
             (extract-entities port entities)))))
 
 (define doctype-handler
   (lambda (port docname systemid internal-subset? seed namespaces)
     (if *debug*
         (begin (display "port: ")
                (write port)
                (newline)
                (display "docname: ")
                (write docname)
                (newline)
                (display "systemid: ")
                (write systemid)
                (newline)
                (display "internal-subset?: ")
                (write internal-subset?)
                (newline)
                (display "seed: ")
                (write seed)
                (newline)))
     (let ((entities (extract-entities port '())))
       (if *debug*
           (begin (write entities)
                  (newline)))
       (values #f entities namespaces seed))))
 
 #;(define (ssax:skip-internal-dtd port)
   (if (not (find-string-from-port? "]>" port))
       (parser-error port "Failed to find ]> terminating the internal DTD subset")))
 
 
 )
