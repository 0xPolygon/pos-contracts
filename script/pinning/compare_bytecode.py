#!/usr/bin/env python3
"""Compare locally compiled runtime bytecode against on-chain runtime bytecode.

Invoked by verify-bytecode.sh. For each pinned contract it reads
  - the forge artifact from <work>/build/out-<solc>/<File>.sol/<Artifact>.json
  - the cached on-chain code from <work>/onchain/<chain>_<address>.hex

Comparison levels:
  MATCH            byte-for-byte identical
  MATCH_NO_META    identical after stripping the trailing CBOR metadata blob
                   (source was reformatted/commented but compiles to the same logic)
  MISMATCH         logic bytecode differs; both stripped blobs are dumped to <work>/diffs/
  NO_CODE          address has no code on-chain
  MISSING_ARTIFACT local build did not produce the expected artifact

Library deployments have their own address embedded at byte offset 1 (PUSH20),
which is masked on both sides. Unresolved link references are masked the same way.
"""

import json
import os
import sys


def strip_metadata(code: bytes):
    """Split trailing CBOR metadata (solidity appends <cbor><2-byte length>)."""
    if len(code) < 4:
        return code, b""
    length = int.from_bytes(code[-2:], "big")
    if length + 2 > len(code):
        return code, b""
    meta = code[-(length + 2):]
    # sanity: solidity metadata is a small CBOR map starting with 0xa1/0xa2/0xa3
    if meta[0] not in (0xA1, 0xA2, 0xA3):
        return code, b""
    return code[: -(length + 2)], meta


def mask(code: bytearray, start: int, length: int):
    code[start : start + length] = b"\x00" * length


def mask_embedded_metadata(code: bytearray) -> int:
    """Zero metadata hashes embedded mid-stream (factories carry the creation
    code of child contracts, which ends in its own CBOR metadata blob)."""
    markers = [
        (b"\xa2\x65\x62\x7a\x7a\x72\x30\x58\x20", 32),  # bzzr0 (solc <= 0.5.11)
        (b"\xa2\x65\x62\x7a\x7a\x72\x31\x58\x20", 32),  # bzzr1 (solc 0.5.12+)
        (b"\xa2\x64\x69\x70\x66\x73\x58\x22", 34),      # ipfs  (solc 0.6+/foundry default)
    ]
    hits = 0
    for marker, hash_len in markers:
        start = 0
        while (pos := bytes(code).find(marker, start)) != -1:
            mask(code, pos + len(marker), hash_len)
            start = pos + len(marker) + hash_len
            hits += 1
    return hits


def main():
    config_path, work = sys.argv[1], sys.argv[2]
    chains = sys.argv[3:]
    cfg = json.load(open(config_path))
    results = []

    for c in cfg["contracts"]:
        if chains and c["chain"] not in chains:
            continue
        if c.get("exclude"):  # legacy / not pinnable to current source — see note
            continue
        entry = {k: c[k] for k in ("chain", "name", "address", "artifact", "solc", "file")}

        src_base = os.path.basename(c["file"])
        # Must mirror verify-bytecode.sh's cache layout, including the bor-chain-id
        # level: the same file+solc can be built at two different chain ids.
        art_path = os.path.join(
            work, "artifacts", c.get("borChainId", "137"), c["solc"], src_base, c["artifact"] + ".json"
        )
        onchain_path = os.path.join(
            work, "onchain", f"{c['chain']}_{c['address'].lower()}.hex"
        )

        if not os.path.exists(art_path):
            entry["status"] = "MISSING_ARTIFACT"
            results.append(entry)
            continue

        art = json.load(open(art_path))
        local_hex = art["deployedBytecode"]["object"].removeprefix("0x")
        onchain_hex = open(onchain_path).read().strip().removeprefix("0x").lower()

        if not onchain_hex:
            entry["status"] = "NO_CODE"
            results.append(entry)
            continue

        # mask placeholders for unresolved library links on both sides
        local_b = bytearray.fromhex(local_hex.replace("_", "0").replace("$", "0"))
        onchain_b = bytearray.fromhex(onchain_hex)
        for refs in art["deployedBytecode"].get("linkReferences", {}).values():
            for sites in refs.values():
                for site in sites:
                    mask(local_b, site["start"], site["length"])
                    if site["start"] + site["length"] <= len(onchain_b):
                        mask(onchain_b, site["start"], site["length"])
        if c.get("isLibrary") and len(local_b) > 21 and len(onchain_b) > 21:
            mask(local_b, 1, 20)  # deployed libraries embed their own address here
            mask(onchain_b, 1, 20)

        if local_b == onchain_b:
            entry["status"] = "MATCH"
        else:
            stripped_local, local_meta = strip_metadata(bytes(local_b))
            stripped_onchain, onchain_meta = strip_metadata(bytes(onchain_b))
            # embedded child-creation-code metadata (factories) is metadata too
            local_logic, onchain_logic = bytearray(stripped_local), bytearray(stripped_onchain)
            mask_embedded_metadata(local_logic)
            mask_embedded_metadata(onchain_logic)
            if local_logic == onchain_logic:
                entry["status"] = "MATCH_NO_META"
                entry["meta_local"] = local_meta.hex()
                entry["meta_onchain"] = onchain_meta.hex()
            else:
                entry["status"] = "MISMATCH"
                entry["len_local"] = len(local_logic)
                entry["len_onchain"] = len(onchain_logic)
                first_diff = next(
                    (i for i, (a, b) in enumerate(zip(local_logic, onchain_logic)) if a != b),
                    min(len(local_logic), len(onchain_logic)),
                )
                entry["first_diff_offset"] = first_diff
                tag = f"{c['chain']}_{c['artifact']}"
                os.makedirs(os.path.join(work, "diffs"), exist_ok=True)
                for suffix, blob in (("local", local_logic), ("onchain", onchain_logic)):
                    with open(os.path.join(work, "diffs", f"{tag}.{suffix}.hex"), "w") as f:
                        f.write(blob.hex())
        results.append(entry)

    with open(os.path.join(work, "results.json"), "w") as f:
        json.dump(results, f, indent=2)

    width = max(len(r["name"]) for r in results) + 2
    print(f"\n{'CONTRACT':<{width}}{'CHAIN':<7}{'SOLC':<9}STATUS")
    print("-" * (width + 30))
    rank = {"MISMATCH": 0, "MISSING_ARTIFACT": 1, "NO_CODE": 2, "MATCH_NO_META": 3, "MATCH": 4}
    for r in sorted(results, key=lambda r: (rank[r["status"]], r["chain"], r["name"])):
        extra = ""
        if r["status"] == "MISMATCH":
            extra = f"  (len {r['len_local']} vs {r['len_onchain']}, first diff @{r['first_diff_offset']})"
        print(f"{r['name']:<{width}}{r['chain']:<7}{r['solc']:<9}{r['status']}{extra}")

    bad = [r for r in results if r["status"] not in ("MATCH", "MATCH_NO_META")]
    meta_only = [r for r in results if r["status"] == "MATCH_NO_META"]
    print(
        f"\n{len(results)} checked: {len(results) - len(bad) - len(meta_only)} exact, "
        f"{len(meta_only)} metadata-only diff, {len(bad)} problems"
    )
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
