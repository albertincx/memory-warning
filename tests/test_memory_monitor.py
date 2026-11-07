import os
import pytest
from memory_monitor import parse_size, format_bytes, detect_system_language, get_t, TRANSLATIONS


def test_parse_size_bytes():
    assert parse_size("1024B") == 1024
    assert parse_size("500") == 500



def test_parse_size_megabytes():
    assert parse_size("500MB") == 500 * 1024 * 1024
    assert parse_size("1024M") == 1024 * 1024 * 1024


def test_parse_size_gigabytes():
    assert parse_size("1GB") == 1024**3
    assert parse_size("1.5G") == 1.5 * (1024**3)
    assert parse_size("2gb") == 2 * (1024**3)


def test_parse_size_invalid():
    with pytest.raises(Exception):
        parse_size("invalid-size")


def test_format_bytes():
    assert format_bytes(512) == "512.0 B"
    assert format_bytes(1024) == "1.0 KB"
    assert format_bytes(1024 * 1024 * 500) == "500.0 MB"
    assert format_bytes(1024**3) == "1.0 GB"


def test_translations_keys_consistency():
    en_keys = set(TRANSLATIONS["en"].keys())
    ru_keys = set(TRANSLATIONS["ru"].keys())
    assert en_keys == ru_keys


def test_get_t():
    t_en = get_t("en")
    assert t_en["notification_title"] == "High Memory Warning"

    t_ru = get_t("ru")
    assert t_ru["notification_title"] == "Предупреждение о памяти"

    # Default fallback should be English
    t_unknown = get_t("unknown")
    assert t_unknown["notification_title"] == "High Memory Warning"


def test_detect_system_language(monkeypatch):
    monkeypatch.setenv("LANG", "ru_RU.UTF-8")
    assert detect_system_language() == "ru"

    monkeypatch.setenv("LANG", "en_US.UTF-8")
    assert detect_system_language() == "en"


def test_menubar_config_defaults():
    from menubar import DEFAULT_CONFIG
    assert "threshold" in DEFAULT_CONFIG
    assert "interval" in DEFAULT_CONFIG
    assert "sound" in DEFAULT_CONFIG
    assert "notifications_enabled" in DEFAULT_CONFIG
    assert "lang" in DEFAULT_CONFIG

