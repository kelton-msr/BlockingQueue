----------------------- MODULE BlockingQueuePoisonPill -----------------------
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS Producers,   (* the (nonempty) set of producers                       *)
          Consumers,   (* the (nonempty) set of consumers                       *)
          BufCapacity  (* the maximum number of messages in the bounded buffer  *)

ASSUME Assumption ==
       /\ Producers # {}                      (* at least one producer *)
       /\ Consumers # {}                      (* at least one consumer *)
       /\ Producers \intersect Consumers = {} (* no thread is both consumer and producer *)
       /\ BufCapacity \in (Nat \ {0})         (* buffer capacity is at least 1 *)

VARIABLES buffer, waitSet, prod, cons
vars == <<buffer, waitSet, prod, cons>>

-----------------------------------------------------------------------------

NotifyOther(t) == 
          LET S == IF t \in Producers THEN waitSet \ Producers ELSE waitSet \ Consumers
          IN IF S # {}
             THEN \E x \in S : waitSet' = waitSet \ {x}
             ELSE UNCHANGED waitSet

Wait(t) == /\ waitSet' = waitSet \cup {t}
           /\ UNCHANGED <<buffer>>
           
-----------------------------------------------------------------------------

Poison == CHOOSE v : TRUE

Put(t, d) ==
    /\ UNCHANGED <<prod, cons>>
    /\ t \notin waitSet
    /\ \/ /\ Len(buffer) < BufCapacity
          /\ buffer' = Append(buffer, d)
          /\ NotifyOther(t)
       \/ /\ Len(buffer) = BufCapacity
          /\ Wait(t)

Get(t) ==
    /\ UNCHANGED <<prod>>
    /\ t \notin waitSet
    /\ \/ /\ buffer # <<>>
          /\ buffer' = Tail(buffer)
          /\ NotifyOther(t)
          /\ IF Head(buffer) = Poison
             \* A "poison pill" terminates this consumer.
             THEN cons' = cons \ {t}
             ELSE UNCHANGED <<cons>>
       \/ /\ buffer = <<>>
          /\ Wait(t)
          /\ UNCHANGED <<cons>>

\* Producers can terminate at any time unless blocked/waiting.
Terminate(t) ==
    /\ UNCHANGED <<buffer, waitSet, cons>>
    /\ t \notin waitSet
    /\ prod' = prod \ {t}

(* 
  A dedicated "janitor" process sends a poisonous pill to each Consumer after
  all producers have terminated. The poisoned pill causes the Consumers to
  terminate in turn.  Synchronization between the Producers and the Janitor is
  left implicit. Possible implementations are discussed below.
*)
Cleanup ==
    \* An implementation could use e.g. a Phaser that Producers arrive
    \* one, and cleanup runs as part of the phaser's onadvance. Obviously,
    \* this simply delegates part of the problem we are trying to solve
    \* to another concurrency primitive, which might be acceptable but
    \* cannot be considered elegant.
    /\ prod = {}
    \* This could be implemented with a basic counter that keeps track of
    \* the number of Consumers that still have to receive a Poison Pill.
    /\ cons # {}
    /\ \/ buffer = <<>>
       \* ...there a fewer Poison messages in the buffer than (non-terminated)
       \* Consumers.
       \/ Cardinality(cons) < Cardinality({i \in DOMAIN buffer: buffer[i]=Poison})
    \* Make one of the producers the janitor that cleans up (we always
    \* choose the same janitor). An implementation may simply create a fresh
    \* process/thread (here it would be a nuisance because of TypeInv...).
    /\ Put(CHOOSE p \in Producers: TRUE, Poison)

-----------------------------------------------------------------------------

(* Initially, the buffer is empty and no thread is waiting. *)
Init == /\ prod = Producers
        /\ cons = Consumers
        /\ buffer = <<>>
        /\ waitSet = {}
        
(* Then, pick a thread out of all running threads and have it do its thing. *)
Next == 
    /\ \/ \E p \in prod: Put(p, p)
       \/ \E p \in prod: Terminate(p)
       \/ \E c \in cons: Get(c)
       \/ Cleanup
        
-----------------------------------------------------------------------------

(* TLA+ is untyped, thus lets verify the range of some values in each state. *)
TypeInv == 
    /\ buffer \in Seq(Producers \cup {Poison})
    /\ Len(buffer) \in 0..BufCapacity
    /\ waitSet \in SUBSET (Consumers \cup Producers)
    /\ prod \in SUBSET Producers
    /\ cons \in SUBSET Consumers

(* No Deadlock *)
NoDeadlock == waitSet # (Producers \cup Consumers)

\* The queue is empty after (global) termination.
QueueEmpty ==
    ((prod \cup cons) = {}) => (buffer = <<>>)

\* The system terminates iff all producers terminate.
GlobalTermination ==
    (prod = {}) ~> [](cons = {})

Spec ==
    Init /\ [][Next]_vars /\ WF_vars(Next) 

=============================================================================