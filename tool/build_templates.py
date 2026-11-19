"""Build the templates bundled with the app from the server migrations.

Set-up must work offline on the first run (implementation plan, C1), so the
standard crops and template items ship inside the app as
assets/templates/standard.json. The rows and their ids are the ones the server
migrations create: ids are md5 of a code string cast to uuid, exactly as
supabase/migrations/0002_wave1_templates.sql does, so the first sync updates
these rows in place instead of adding copies.

Later template migrations are applied by the RELEASES list below; add one
entry for each new migration that changes templates, then run:

    python tool/build_templates.py

test/core/sync/bundled_templates_test.dart fails when the asset and the
migrations disagree.
"""

import hashlib
import json
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..")
MIGRATION = os.path.join(ROOT, "supabase", "migrations", "0002_wave1_templates.sql")
OUT = os.path.join(ROOT, "assets", "templates", "standard.json")

# (migration, list type, crop code or None, item code, changes)
RELEASES = [
    # 0005_standard_units.sql: para retired, template release 2
    ("0005", "unit", "paddy", "para", {"is_active": False, "template_version": 2}),
]


def md5_uuid(text):
    h = hashlib.md5(text.encode("utf-8")).hexdigest()
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


TOKEN = re.compile(r"\s*(?:'((?:[^']|'')*)'|(null)|(-?\d+(?:\.\d+)?)|(\w+\([^)]*\)::uuid))\s*")


def parse_tuple(body):
    """The values of one SQL tuple: strings, null and numbers."""
    values = []
    pos = 0
    while pos < len(body):
        m = TOKEN.match(body, pos)
        if not m:
            raise ValueError(f"cannot read: {body[pos:]}")
        if m.group(1) is not None:
            values.append(m.group(1).replace("''", "'"))
        elif m.group(2):
            values.append(None)
        elif m.group(3):
            values.append(int(m.group(3)))
        else:
            values.append(m.group(4))
        pos = m.end()
        if pos < len(body) and body[pos] == ",":
            pos += 1
    return values


def tuples(sql):
    """Every '(...)' line of a VALUES list, as parsed tuples."""
    out = []
    for line in sql.splitlines():
        line = line.strip()
        if not re.match(r"\((?:'|null|md5)", line):
            continue
        line = line.rstrip(",")
        if line.endswith(";"):
            continue
        out.append(parse_tuple(line[1:-1]))
    return out


def main():
    sql = open(MIGRATION, encoding="utf-8").read()
    crops_sql, items_sql = sql.split("insert into public.template_items", 1)

    crops = []
    by_code = {}
    for row in tuples(crops_sql):
        _, code, name_ml, name_en, kind, unit = row
        crop = {
            "id": md5_uuid(f"thottam:crop:{code}"),
            "code": code,
            "name_ml": name_ml,
            "name_en": name_en,
            "kind": kind,
            "default_unit": unit,
        }
        crops.append(crop)
        by_code[code] = crop["id"]

    items = []
    for row in tuples(items_sql):
        crop, list_type, code, name_ml, name_en, sort_order, data = row
        merged = json.loads(data)
        merged["ml_review"] = True
        items.append({
            "id": md5_uuid(f"thottam:item:{crop or '*'}:{list_type}:{code}"),
            "crop_id": by_code[crop] if crop else None,
            "list_type": list_type,
            "code": code,
            "name_ml": name_ml,
            "name_en": name_en,
            "data": merged,
            "sort_order": sort_order,
            "is_active": True,
            "template_version": 1,
        })

    for _, list_type, crop, code, changes in RELEASES:
        crop_id = by_code[crop] if crop else None
        matched = [i for i in items
                   if i["list_type"] == list_type and i["code"] == code and i["crop_id"] == crop_id]
        if len(matched) != 1:
            raise ValueError(f"release step matches {len(matched)} items: {list_type} {crop} {code}")
        matched[0].update(changes)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"crops": crops, "template_items": items}, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"{len(crops)} crops, {len(items)} items -> {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
