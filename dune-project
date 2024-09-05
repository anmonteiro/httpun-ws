(lang dune 3.0)

(name httpun-ws)

(generate_opam_files true)

(source
 (github anmonteiro/httpun-ws))

(authors
 "Spiros Eliopoulos <spiros@inhabitedtype.com>"
 "Antonio Nuno Monteiro <anmonteiro@gmail.com>")

(maintainers "Antonio Nuno Monteiro <anmonteiro@gmail.com>")

(homepage "https://github.com/anmonteiro/httpun-ws")

(bug_reports "https://github.com/anmonteiro/httpun-ws/issues")

(license "BSD-3-clause")

(package
 (name httpun-ws)
 (synopsis "Websocket implementation for httpun")
 (depends
  (ocaml
   (>= "4.08"))
  (base64
   (>= "3.0.0"))
  bigstringaf
  (angstrom
   (>= "0.14.0"))
  (faraday
   (>= "0.8.0"))
  (gluten
   (>= "0.2.0"))
  httpun
  (alcotest :with-test)))

(package
 (name httpun-ws-lwt)
 (synopsis "Lwt support for httpun")
 (depends
  (ocaml
   (>= "4.08"))
  (httpun-ws
   (= :version))
  lwt
  (digestif
   (>= "1.2.0"))
  (gluten-lwt
   (>= "0.2.0"))))

(package
 (name httpun-ws-lwt-unix)
 (synopsis "Lwt + unix support for httpun-ws")
 (depends
  (ocaml
   (>= "4.08"))
  (httpun-ws-lwt
   (= :version))
  (gluten-lwt-unix
   (>= "0.2.0"))))

(package
 (name httpun-ws-eio)
 (synopsis "Eio support for httpun")
 (depends
  (ocaml
   (>= "4.08"))
  (httpun-ws
   (= :version))
  (digestif
   (>= "1.2.0"))
  (gluten-eio
   (>= "0.2.1"))))

(package
 (name httpun-ws-mirage)
 (synopsis "Mirage support for httpun")
 (depends
  (ocaml
   (>= "4.08"))
  (httpun-ws-lwt
   (= :version))
  (gluten-mirage
   (>= "0.5.0"))
  (mirage-flow
   (>= "2.0.0"))
  cstruct))

(package
 (name httpun-ws-async)
 (synopsis "Mirage support for httpun")
 (depends
  (ocaml
   (>= "4.08"))
  (httpun-ws
   (= :version))
  (async
   (>= "v0.15.0"))
  (gluten-async
   (>= "0.5.0"))
  (digestif
   (>= "1.2.0"))))
