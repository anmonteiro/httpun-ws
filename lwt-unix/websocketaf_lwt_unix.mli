module Server :
  Websocketaf_lwt.Server
    with type socket := Lwt_unix.file_descr
     and type addr := Unix.sockaddr

module Client :
 Websocketaf_lwt.Client with type socket := Lwt_unix.file_descr
