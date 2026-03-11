{ pkgs }:

let
  py = pkgs.python27Packages;
  buildPythonPackage = py.buildPythonPackage;
  fetchPypi = py.fetchPypi;
  openssl_1_1 = pkgs.openssl_1_1.overrideAttrs (_: {
    doCheck = false;
  });

  mkLegacyPythonPackage =
    { pname
    , pypiName ? pname
    , version
    , hash
    , extension ? "tar.gz"
    , format ? "setuptools"
    , propagatedBuildInputs ? [ ]
    , nativeBuildInputs ? [ ]
    , buildInputs ? [ ]
    , pythonImportsCheck ? [ ]
    , postPatch ? ""
    , postInstall ? ""
    }:
    buildPythonPackage {
      inherit pname version format propagatedBuildInputs nativeBuildInputs buildInputs pythonImportsCheck postPatch postInstall;
      src = fetchPypi {
        pname = pypiName;
        inherit version extension hash;
      };
      doCheck = false;
    };

  six = mkLegacyPythonPackage {
    pname = "six";
    version = "1.16.0";
    hash = "sha256-HmHDdHehYmRY4297HYKqXJsJT6SAKJIHLknenGDEySY=";
    pythonImportsCheck = [ "six" ];
  };

  typing = mkLegacyPythonPackage {
    pname = "typing";
    version = "3.10.0.0";
    hash = "sha256-E7StIR9U3b+T5ZAamWex4HcgwdG3jVlqxqQ5ZBqhsTA=";
    pythonImportsCheck = [ "typing" ];
  };

  ipaddress = mkLegacyPythonPackage {
    pname = "ipaddress";
    version = "1.0.23";
    hash = "sha256-t/jgNpWAu0ok1bodfMKWYKSmmHdj+vHYqARoMOAg5+I=";
    pythonImportsCheck = [ "ipaddress" ];
  };

  enum34 = mkLegacyPythonPackage {
    pname = "enum34";
    version = "1.1.10";
    hash = "sha256-zOanR37YFr0lQtA9U9ufDbk13QE7cPM2qVxzl5KJ8kg=";
    pythonImportsCheck = [ "enum" ];
  };

  futures = mkLegacyPythonPackage {
    pname = "futures";
    version = "3.4.0";
    hash = "sha256-PsjO7NG4VUeqdTnB241rKmJFQF3kJ+R4CAm29WoY/dI=";
    pythonImportsCheck = [ "concurrent.futures" ];
  };

  trollius = mkLegacyPythonPackage {
    pname = "trollius";
    version = "2.1.post2";
    hash = "sha256-FbE0UTK/awtEdB3ZsS+trQ1MHWCjHyL/M+n9F9uy46U=";
    propagatedBuildInputs = [ futures six typing ];
    pythonImportsCheck = [ "trollius" ];
  };

  attrs = mkLegacyPythonPackage {
    pname = "attrs";
    version = "21.4.0";
    hash = "sha256-YmuoI0IR25joad92IwoTfExAoS1yRFxF1fW3FvB24v0=";
    pythonImportsCheck = [ "attr" ];
  };

  automat = mkLegacyPythonPackage {
    pname = "Automat";
    version = "0.8.0";
    hash = "sha256-JpoJ37Bjo7B4mD9Jdtg/Cg0+bnqvjifY3xCV4J3EpIQ=";
    propagatedBuildInputs = [ attrs six ];
    pythonImportsCheck = [ "automat" ];
  };

  constantly = mkLegacyPythonPackage {
    pname = "constantly";
    version = "15.1.0";
    hash = "sha256-WGNy65IFmHPinrpPneyDgVQbTTg0ZgcH+vi6WRRt/DU=";
    pythonImportsCheck = [ "constantly" ];
  };

  idna = mkLegacyPythonPackage {
    pname = "idna";
    version = "2.10";
    hash = "sha256-sweHL4VbGGMs4MIcXkW+eMDqeuTBXIKMIHiLJpIes/Y=";
    pythonImportsCheck = [ "idna" ];
  };

  hyperlink = mkLegacyPythonPackage {
    pname = "hyperlink";
    version = "21.0.0";
    hash = "sha256-Qnr5V9qli8kJRxxsQPdMVFD6Ej3Qk/xT79LpHScFpWs=";
    propagatedBuildInputs = [ idna typing ];
    pythonImportsCheck = [ "hyperlink" ];
  };

  incremental = mkLegacyPythonPackage {
    pname = "Incremental";
    pypiName = "incremental";
    version = "16.10.1";
    hash = "sha256-FK1rcg7Eeq1snKqD5H2xhD4rm5h0LaXdoI4WqZ9AA0I=";
    pythonImportsCheck = [ "incremental" ];
  };

  linecache2 = mkLegacyPythonPackage {
    pname = "linecache2";
    version = "1.0.0";
    hash = "sha256-Syb/TnEQ23butvWntkqCYjg51ZXCA47tpmLyott46Xw=";
    pythonImportsCheck = [ "linecache2" ];
  };

  traceback2 = mkLegacyPythonPackage {
    pname = "traceback2";
    version = "1.4.0";
    hash = "sha256-BazGegmYDC7P7dNCP3rgEEg57MtV/GRXc+HKoJUcMDA=";
    propagatedBuildInputs = [ linecache2 six ];
    pythonImportsCheck = [ "traceback2" ];
  };

  argparse = mkLegacyPythonPackage {
    pname = "argparse";
    version = "1.4.0";
    hash = "sha256-YrCJpVvh2JSc0rx+DfC9254Cj678jDIDjMhIYq791uQ=";
    pythonImportsCheck = [ "argparse" ];
  };

  pyhamcrest = mkLegacyPythonPackage {
    pname = "PyHamcrest";
    version = "1.10.1";
    hash = "sha256-964Z3f1x8RpCG87JYI1wjA+rgW25i1H9vGcqbZmjCHQ=";
    propagatedBuildInputs = [ six ];
    pythonImportsCheck = [ "hamcrest" ];
  };

  pyasn1 = mkLegacyPythonPackage {
    pname = "pyasn1";
    version = "0.4.8";
    hash = "sha256-rvd8n7lKOsWI6HhBIIvexGRHHZhxvVBQoofMmkdc0Lo=";
    pythonImportsCheck = [ "pyasn1" ];
  };

  pyasn1-modules = mkLegacyPythonPackage {
    pname = "pyasn1-modules";
    version = "0.2.8";
    hash = "sha256-kF+ExxIjCyxZLBlHDTyo1VLecmBQ0dFxYoKh9hRr5l4=";
    propagatedBuildInputs = [ pyasn1 ];
    pythonImportsCheck = [ "pyasn1_modules" ];
  };

  markupsafe = mkLegacyPythonPackage {
    pname = "MarkupSafe";
    version = "1.1.1";
    hash = "sha256-KYcukoOXZeVGgou3dUpoxBjZJ80GT9Rwj6uf6ci7EWs=";
    pythonImportsCheck = [ "markupsafe" ];
  };

  jinja2 = mkLegacyPythonPackage {
    pname = "Jinja2";
    version = "2.11.3";
    hash = "sha256-ptWEM94K6AA0fKsfowQ867q+i6qdKeZo8cdoy4ejM8Y=";
    propagatedBuildInputs = [ markupsafe ];
    pythonImportsCheck = [ "jinja2" ];
  };

  werkzeug = mkLegacyPythonPackage {
    pname = "Werkzeug";
    version = "1.0.1";
    hash = "sha256-bICx5a02ZSkOo5MguR4b4eDV9gZSuWSjBwIW3oPS5Hw=";
    pythonImportsCheck = [ "werkzeug" ];
  };

  zope-interface = mkLegacyPythonPackage {
    pname = "zope.interface";
    version = "4.6.0";
    hash = "sha256-Gz0Nyrx8kLRw5Z44qayqNhvkOzpupkTABjlRlkcX8OU=";
    postInstall = ''
      cat > "$out/lib/python2.7/site-packages/zope/__init__.py" <<'EOF'
      from pkgutil import extend_path
      __path__ = extend_path(__path__, __name__)
      EOF
    '';
  };

  pycparser = mkLegacyPythonPackage {
    pname = "pycparser";
    version = "2.21";
    hash = "sha256-5kT97BL3hy+GxY/3kNpFYhixD4Y5cCSVFtYKXqyncgY=";
    pythonImportsCheck = [ "pycparser" ];
  };

  cffi = mkLegacyPythonPackage {
    pname = "cffi";
    version = "1.15.1";
    hash = "sha256-1AC/uaN7E1ElPLQCZxzqfom97MKU6AFqcH9tHYrJNPk=";
    nativeBuildInputs = [ py.setuptools pkgs.pkg-config ];
    buildInputs = [ pkgs.libffi ];
    propagatedBuildInputs = [ pycparser ];
    pythonImportsCheck = [ "cffi" ];
  };

  cryptography = mkLegacyPythonPackage {
    pname = "cryptography";
    version = "3.3.2";
    hash = "sha256-WmDTeAFJ4Tt6b/etZSaziEY1TRGhXiEGjlcHPinhm+0=";
    nativeBuildInputs = [ py.setuptools pkgs.pkg-config ];
    buildInputs = [ openssl_1_1 pkgs.libffi ]
      ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.libiconv ];
    propagatedBuildInputs = [ cffi enum34 ipaddress six ];
    pythonImportsCheck = [ "cryptography" ];
  };

  pyopenssl = mkLegacyPythonPackage {
    pname = "pyOpenSSL";
    version = "19.1.0";
    hash = "sha256-miRJSyYCqvQCvlyeMKC4LUpcZ1KP6PtHXj87wA3WlQc=";
    propagatedBuildInputs = [ cryptography six ];
    pythonImportsCheck = [ "OpenSSL" ];
  };

  service-identity = mkLegacyPythonPackage {
    pname = "service-identity";
    pypiName = "service_identity";
    version = "18.1.0";
    hash = "sha256-CFilSqvFtFnRqvqKUY7SCBooUIfzSf4+VRl5iSMuLi0=";
    propagatedBuildInputs = [ attrs pyasn1 pyasn1-modules cryptography pyopenssl six ];
    pythonImportsCheck = [ "service_identity" ];
  };

  txaio = mkLegacyPythonPackage {
    pname = "txaio";
    version = "2.1.0";
    hash = "sha256-uU49vIN2C2iVUWD8YaLDTieY96kMQWclYPQN/SlGqGQ=";
    propagatedBuildInputs = [ six trollius ];
    pythonImportsCheck = [ "txaio" ];
  };

  twisted = mkLegacyPythonPackage {
    pname = "Twisted";
    version = "19.10.0";
    hash = "sha256-c5S6fycq5yKnTz2Wnc9Zm8TvCTvDkgOHSKSQ8XJKUV0=";
    extension = "tar.bz2";
    propagatedBuildInputs = [
      attrs
      automat
      constantly
      hyperlink
      incremental
      pyhamcrest
      typing
      zope-interface
    ];
    pythonImportsCheck = [ "twisted" ];
  };

  klein = mkLegacyPythonPackage {
    pname = "klein";
    version = "17.10.0";
    hash = "sha256-MKrw14qYfV2/4JaKBzZ60Mc+AoI8yO70xU+Aq4SDcNA=";
    propagatedBuildInputs = [ incremental twisted werkzeug ];
    pythonImportsCheck = [ "klein" ];
  };

  unittest2 = mkLegacyPythonPackage {
    pname = "unittest2";
    version = "1.1.0";
    hash = "sha256-IogqDkGMKE4fcYqCKzsCKUTVPS2QjhaQsxmp0+ssBXk=";
    propagatedBuildInputs = [ argparse six traceback2 ];
    postPatch = ''
      substituteInPlace setup.py --replace "VERSION = late_version()" "VERSION = '1.1.0'"
    '';
    pythonImportsCheck = [ "unittest2" ];
  };

  autobahn = mkLegacyPythonPackage {
    pname = "autobahn";
    version = "0.10.9";
    hash = "sha256-P+zB4qJqBCESjdz7Tld/C8Zp3WXQ4P2tHHc5ZcvO91o=";
    propagatedBuildInputs = [ six txaio twisted zope-interface ];
    pythonImportsCheck = [ "autobahn" ];
  };

in
mkLegacyPythonPackage {
  pname = "autobahntestsuite";
  version = "25.10.1";
  hash = "sha256-sIPW4VMw/Bbz5fCXXM4rFfIb+gxtsJVHMWsYUsbb1t8=";
  propagatedBuildInputs = [
    py.setuptools
    txaio
    incremental
    pyopenssl
    cryptography
    twisted
    zope-interface
    jinja2
    markupsafe
    werkzeug
    klein
    service-identity
    unittest2
    six
    autobahn
  ];
  pythonImportsCheck = [ "autobahntestsuite" ];
}
