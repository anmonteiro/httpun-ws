(*----------------------------------------------------------------------------
 *  Copyright (c) 2018 Inhabited Type LLC.
 *  Copyright (c) 2021 António Nuno Monteiro
 *
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions
 *  are met:
 *
 *  1. Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *
 *  2. Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 *  3. Neither the name of the author nor the names of his contributors
 *     may be used to endorse or promote products derived from this software
 *     without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE CONTRIBUTORS ``AS IS'' AND ANY EXPRESS
 *  OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 *  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 *  DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE FOR
 *  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 *  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 *  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 *  STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 *  ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 *  POSSIBILITY OF SUCH DAMAGE.
 *----------------------------------------------------------------------------*)

(* TODO(anmonteiro):
 *  - automatic chunking of messages?
*)

module IOVec = Httpun.IOVec

type t =
  { faraday : Faraday.t
  ; mutable read_scheduled : bool
  ; mutable on_eof : unit -> unit
  ; mutable eof_has_been_called : bool
  ; mutable on_read : Bigstringaf.t -> off:int -> len:int -> unit
  ; when_ready_to_read : Optional_thunk.t
  }

let default_on_eof = Sys.opaque_identity (fun () -> ())
let default_on_read = Sys.opaque_identity (fun _ ~off:_ ~len:_ -> ())

let create buffer ~when_ready_to_read =
  { faraday = Faraday.of_bigstring buffer
  ; read_scheduled = false
  ; eof_has_been_called = false
  ; on_eof = default_on_eof
  ; on_read = default_on_read
  ; when_ready_to_read
  }

let create_empty () =
  let t = create Bigstringaf.empty ~when_ready_to_read:Optional_thunk.none in
  Faraday.close t.faraday;
  t

let is_closed t = Faraday.is_closed t.faraday
let unsafe_faraday t = t.faraday
let ready_to_read t = Optional_thunk.call_if_some t.when_ready_to_read

let rec do_execute_read t on_eof on_read =
  match Faraday.operation t.faraday with
  | `Yield -> ()
  | `Close ->
    t.read_scheduled <- false;
    t.on_eof <- default_on_eof;
    t.on_read <- default_on_read;
    if not t.eof_has_been_called
    then (
      t.eof_has_been_called <- true;
      on_eof ())
  (* [Faraday.operation] never returns an empty list of iovecs *)
  | `Writev [] -> assert false
  | `Writev (iovec :: _) ->
    t.read_scheduled <- false;
    t.on_eof <- default_on_eof;
    t.on_read <- default_on_read;
    let { IOVec.buffer; off; len } = iovec in
    Faraday.shift t.faraday len;
    on_read buffer ~off ~len;
    execute_read t

and execute_read t =
  if t.read_scheduled then do_execute_read t t.on_eof t.on_read

let schedule_read t ~on_eof ~on_read =
  if t.read_scheduled
  then failwith "Payload.schedule_read: reader already scheduled";
  if not (is_closed t)
  then (
    t.read_scheduled <- true;
    t.on_eof <- on_eof;
    t.on_read <- on_read);
  do_execute_read t on_eof on_read;
  ready_to_read t

let close t =
  Faraday.close t.faraday;
  execute_read t;
  ready_to_read t

let has_pending_output t = Faraday.has_pending_output t.faraday
let is_read_scheduled t = t.read_scheduled

type input_state =
  | Ready
  | Wait
  | Complete

let input_state t : input_state =
  if is_closed t then Complete else if is_read_scheduled t then Ready else Wait
