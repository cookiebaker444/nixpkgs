{ lib
, buildPythonPackage
, fetchPypi
, dateutil
, flask_1
, pyjwt1
, six
, werkzeug
, pytest
}:

buildPythonPackage rec {
  pname = "Flask-JWT-Extended";
  version = "3.25.1";

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-u/RGf0HFbPH9ilhw0lVvQZxXKq0rQIV1dYHD+bTXdno=";
  };

  propagatedBuildInputs = [
    flask_1
    pyjwt1
    six
    werkzeug
  ];

  checkInputs = [
    dateutil
    pytest
  ];

  checkPhase = ''
    pytest --deselect tests/test_view_decorators.py::test_expired_token tests/
  '';

  meta = with lib; {
    description = "JWT extension for Flask";
    homepage = "https://flask-jwt-extended.readthedocs.io/";
    license = licenses.mit;
    maintainers = with maintainers; [ gerschtli ];
  };
}
