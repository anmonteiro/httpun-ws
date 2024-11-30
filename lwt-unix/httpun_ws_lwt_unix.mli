module Server :
  Httpun_ws_lwt.Server
  with type socket := Lwt_unix.file_descr
   and type addr := Unix.sockaddr

module Client : Httpun_ws_lwt.Client with type socket := Lwt_unix.file_descr
