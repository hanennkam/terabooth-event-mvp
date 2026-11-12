import importlib.util
from pathlib import Path
from types import SimpleNamespace


def _module():
    path = Path(__file__).resolve().parents[1] / "validation" / "validate_bridge.py"
    spec = importlib.util.spec_from_file_location("validation_validate_bridge", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_windows_version_report_uses_documented_attributes_without_asdict():
    module = _module()

    # CPython's WindowsVersion shape, deliberately without a guaranteed
    # _asdict() method (the source of the real Windows 3.14 failure).
    version = SimpleNamespace(
        major=10,
        minor=0,
        build=22631,
        platform=2,
        service_pack="",
        service_pack_major=0,
        service_pack_minor=0,
        suite_mask=0,
        product_type=1,
    )
    assert not hasattr(version, "_asdict")
    info = module.windows_version_info(version)
    assert info["major"] == 10
    assert info["minor"] == 0
    assert info["build"] == 22631
    assert info["platform"] == 2
    assert info["service_pack"] == ""
    assert "suite_mask" in info
    assert "product_type" in info
    assert not hasattr(info, "_asdict")
