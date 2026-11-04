#lang racket/base

(require racket/list
         racket/string
         "../security/security.rkt")

(struct capability (name mutating description) #:transparent)

(define the-capabilities
  (list (capability "routes" #f "walk the routing: every key, every layer")
        (capability "keys" #f "list the keys and what each one means")
        (capability "tasks" #f "list the task table")
        (capability "agent" #f "show the agent's state and its pins")
        (capability "audit" #f "show the audit: what changed, and who changed it")
        (capability "task" #t "run one task of the task table")
        (capability "bake" #t "bake the meaning side into the hot path")
        (capability "send" #t "send the bundle to the agent")
        (capability "checkpoint" #t "make a checkpoint of the tree")
        (capability "rollback" #t "put the tree back at a checkpoint")
        (capability "stop" #t "throw or clear the stop switch")
        (capability "permit" #t "answer a permission ask")
        (capability "agent-end" #t "end the agent's session")
        (capability "audit-accept" #t "accept a change of the audit")
        (capability "audit-undo" #t "undo a change of the audit")
        (capability "plugin" #f "show the plugins the editor knows, and what pm says")
        (capability "plugin-register" #t "register a plugin from its manifest")
        (capability "plugin-install" #t "ask pm to install a plugin")
        (capability "plugin-call" #t "call one seam call on one plugin")))

(define (capability-names)
  (sort (map capability-name the-capabilities) string<?))

(define (capability-of name)
  (for/or ([cap (in-list the-capabilities)])
    (and (string=? (capability-name cap) name) cap)))

(define (declaration-agrees? name)
  (define cap (capability-of name))
  (and cap (eq? (state-changing? name) (capability-mutating cap))))

(define (declaration-honest?)
  (for/first ([cap (in-list the-capabilities)]
               #:unless (eq? (state-changing? (capability-name cap))
                             (capability-mutating cap)))
    (capability-name cap)))

(provide capability
         capability-name
         capability-mutating
         capability-description
         the-capabilities
         capability-names
         capability-of
         declaration-agrees?
         declaration-honest?)
