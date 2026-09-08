#!/usr/bin/env python3
"""Validate product metadata and executables; codesigning/entitlements require separate gates."""

import argparse
from collections.abc import Callable
from pathlib import Path, PurePosixPath
import plistlib
import stat
import sys
import zipfile


class ArtifactError(ValueError):
    pass


def read_plist(read: Callable[[str], bytes], name: str) -> dict:
    try:
        value = plistlib.loads(read(name))
    except (plistlib.InvalidFileException, ValueError, OverflowError):
        raise ArtifactError("Info.plist ausente ou invalido.") from None
    if not isinstance(value, dict):
        raise ArtifactError("Info.plist deve conter um dicionario.")
    return value


def resolved_string(info: dict, field: str) -> str:
    value = info.get(field)
    if not isinstance(value, str) or not value.strip() or "$(" in value:
        raise ArtifactError("Bundle requer identificador, versao/build e executavel resolvidos.")
    return value


def validate_products(
    entries: set[str],
    read: Callable[[str], bytes],
    size: Callable[[str], int],
    bundle_id: str,
) -> dict[str, dict]:
    bundles = set()
    for name in entries:
        parts = PurePosixPath(name).parts
        for index, part in enumerate(parts):
            if part.endswith((".app", ".appex")):
                bundles.add("/".join(parts[:index + 1]))
    primary = [item for item in bundles if item.startswith("Payload/") and item.count("/") == 1 and item.endswith(".app")]
    if len(primary) != 1:
        raise ArtifactError("Artefato requer exatamente um app principal.")
    app = primary[0]
    watch = [item for item in bundles if item.startswith(app + "/Watch/") and item.count("/") == 3 and item.endswith(".app")]
    widget = [item for item in bundles if item.startswith(app + "/PlugIns/") and item.count("/") == 3 and item.endswith(".appex")]
    if len(watch) != 1 or len(widget) != 1 or bundles != {app, *watch, *widget}:
        raise ArtifactError("Artefato requer somente o app, um Watch app e uma extensao de widgets embarcados.")

    products = {}
    for role, location, expected_id in (
        ("app", app, bundle_id),
        ("watch", watch[0], bundle_id + ".watch"),
        ("widget", widget[0], bundle_id + ".widgets"),
    ):
        info = read_plist(read, location + "/Info.plist")
        fields = {
            field: resolved_string(info, field)
            for field in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion", "CFBundleExecutable")
        }
        if fields["CFBundleIdentifier"] != expected_id:
            raise ArtifactError("Bundle ID de produto inesperado.")
        executable = fields["CFBundleExecutable"]
        if executable in (".", "..") or "/" in executable or "\\" in executable or size(location + "/" + executable) <= 0:
            raise ArtifactError("Cada produto requer um executavel nao vazio dentro do bundle.")
        if role != "app" and any(fields[key] != products["app"][key] for key in ("CFBundleShortVersionString", "CFBundleVersion")):
            raise ArtifactError("App, Watch e widgets devem ter a mesma versao e build.")
        if role == "watch" and info.get("WKCompanionAppBundleIdentifier") != bundle_id:
            raise ArtifactError("Watch app deve apontar para o app principal.")
        if role == "widget" and info.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
            raise ArtifactError("Extensao embarcada deve ser WidgetKit.")
        fields["bundlePath"] = location
        if role == "app":
            key = info.get("RevenueCatAPIKey")
            if (not isinstance(key, str) or not key.startswith("appl_") or len(key) <= 5
                    or "$(" in key or any(character.isspace() for character in key)):
                raise ArtifactError("Release requer RevenueCatAPIKey publica Apple (appl_). Configure a chave de producao e gere outro archive; Test Store e chave ausente/placeholder nao podem ser publicados.")
            for key in ("RevenueCatAPIKey", "RevenueCatEntitlementID", "RevenueCatOfferingID"):
                fields[key] = info.get(key)
        products[role] = fields
    return products


def validate_archive(archive: Path, bundle_id: str) -> dict[str, dict]:
    archive = archive.resolve()
    applications = archive / "Products" / "Applications"
    applications.resolve().relative_to(archive)

    def file_path(name: str) -> Path:
        result = (applications / name.removeprefix("Payload/")).resolve()
        result.relative_to(applications)
        return result

    def size(name: str) -> int:
        candidate = file_path(name)
        return candidate.stat().st_size if candidate.is_file() else 0

    def read(name: str) -> bytes:
        if not 0 < size(name) <= 1024 * 1024:
            raise ArtifactError("Info.plist ausente, vazio ou acima de 1 MiB.")
        return file_path(name).read_bytes()

    entries = {"Payload/" + item.relative_to(applications).as_posix() for item in applications.rglob("*")}
    products = validate_products(entries, read, size, bundle_id)
    metadata = plistlib.loads((archive / "Info.plist").read_bytes())
    expected_path = products["app"]["bundlePath"].replace("Payload/", "Applications/", 1)
    if metadata.get("ApplicationProperties", {}).get("ApplicationPath") != expected_path:
        raise ArtifactError("ApplicationProperties deve identificar o unico app principal do archive.")
    return products


def validate_ipa(ipa: Path, bundle_id: str) -> dict[str, dict]:
    with zipfile.ZipFile(ipa) as package:
        members = package.infolist()
        names = [item.filename.rstrip("/") for item in members]
        if len(set(names)) != len(names):
            raise ArtifactError("IPA contem caminhos duplicados.")
        for name in names:
            if name.startswith("/") or "\\" in name or any(part in ("", ".", "..") for part in name.split("/")):
                raise ArtifactError("IPA contem caminho invalido.")
        entries = dict(zip(names, members))

        def size(name: str) -> int:
            member = entries.get(name)
            if member is None or member.is_dir() or stat.S_ISLNK(member.external_attr >> 16):
                return 0
            return member.file_size

        def read(name: str) -> bytes:
            if not 0 < size(name) <= 1024 * 1024:
                raise ArtifactError("Info.plist ausente, vazio ou acima de 1 MiB.")
            return package.read(entries[name])

        return validate_products(set(entries), read, size, bundle_id)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--ipa", type=Path, help="Compare an exported IPA with the archive without extracting it.")
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--version", help="Expected marketing version, when independently known.")
    parser.add_argument("--build", help="Expected build number, when independently known.")
    args = parser.parse_args()
    try:
        archive = validate_archive(args.archive, args.bundle_id)
        if args.version is not None and archive["app"]["CFBundleShortVersionString"] != args.version:
            raise ArtifactError("Versao do archive difere da versao esperada.")
        if args.build is not None and archive["app"]["CFBundleVersion"] != args.build:
            raise ArtifactError("Build do archive difere do build esperado.")
        if args.ipa is not None and validate_ipa(args.ipa, args.bundle_id) != archive:
            raise ArtifactError("Metadados dos produtos no IPA diferem do archive validado.")
    except ArtifactError as error:
        print("ERRO: " + str(error), file=sys.stderr)
        return 6
    except (OSError, ValueError, KeyError, TypeError, AttributeError, RuntimeError, zipfile.BadZipFile, plistlib.InvalidFileException):
        print("ERRO: estrutura do archive/IPA ausente, ilegivel ou invalida.", file=sys.stderr)
        return 6
    print("Archive configuration validated." if args.ipa is None else "IPA metadata matches validated archive.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
