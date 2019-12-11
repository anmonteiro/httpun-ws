(*----------------------------------------------------------------------------
    Copyright (c) 2018 Inhabited Type LLC.
    Copyright (c) 2019 António Nuno Monteiro

    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    3. Neither the name of the author nor the names of his contributors
       may be used to endorse or promote products derived from this software
       without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE CONTRIBUTORS ``AS IS'' AND ANY EXPRESS
    OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE FOR
    ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
    DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
    OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
    HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
    STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
  ----------------------------------------------------------------------------*)

open Websocketaf

module type IO = sig
  type socket
  type addr

  (** The region [[off, off + len)] is where read bytes can be written to *)
  val read
    :  socket
    -> Bigstringaf.t
    -> off:int
    -> len:int
    -> [ `Eof | `Ok of int ] Lwt.t

  val writev
    : socket
    -> Faraday.bigstring Faraday.iovec list
    -> [ `Closed | `Ok of int ] Lwt.t

  val shutdown_send : socket -> unit

  val shutdown_receive : socket -> unit

  val close : socket -> unit Lwt.t
end

module type Server = sig
  type socket

  type addr

  val create_connection_handler
    :  ?config : Httpaf.Config.t
    -> websocket_handler : (addr -> Wsd.t -> Server_connection.input_handlers)
    -> error_handler : (addr -> Httpaf.Server_connection.error_handler)
    -> (addr -> socket -> unit Lwt.t)

  val create_upgraded_connection_handler
    :  ?config : Httpaf.Config.t
    -> websocket_handler : (addr -> Wsd.t -> Server_connection.input_handlers)
    -> error_handler : Server_connection.error_handler
    -> (addr -> socket -> unit Lwt.t)

  val respond_with_upgrade
  : ?headers : Httpaf.Headers.t
  -> (socket, unit Lwt.t) Httpaf.Reqd.t
  -> (socket -> unit Lwt.t)
  -> (unit, string) Lwt_result.t
end


module type Client = sig
  type socket

  (* Perform HTTP/1.1 handshake and upgrade to WS. *)
  val connect
    :  nonce             : string
    -> host              : string
    -> port              : int
    -> resource          : string
    -> error_handler : (Client_connection.error -> unit)
    -> websocket_handler : (Wsd.t -> Client_connection.input_handlers)
    -> socket
    -> unit Lwt.t

  (* Starts speaking websockets, doesn't perform the handshake. *)
  val create
    :  websocket_handler : (Wsd.t -> Client_connection.input_handlers)
    -> socket
    -> unit Lwt.t
end

