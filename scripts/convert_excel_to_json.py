# scripts/convert_excel_to_json.py
import json
import os
import sys
import unicodedata
from datetime import datetime, date
import pandas as pd

EXCEL_CANDIDATES = [
    "Template_Proyectos_Dashboard.xlsx",
    "Template_Proyectos_Dashboard.xlsm",
    "Template_Proyectos_Dashboard.xls",
]
OUTPUT_JSON = os.path.join(os.path.dirname(__file__), "..", "data.json")

HEADER_MAP = {
    "cliente":  {"cliente","account","empresa"},
    "proyecto": {"proyecto","project","nombre proyecto"},
    "tareas":   {"tareas","tarea","actividad","actividad/tarea","nombre tarea","task"},
    "estatus":  {"estatus","estado","status"},
    "owner":    {"owner","responsable","asignado","ejecutor"},
    "email":    {"correo","email","owner email","mail","e-mail","correo owner"},
    "deadline": {"deadline","fecha limite","fecha límite","vencimiento","due date"},
}
SHEET_PREFERENCE = ["Proyectos", "Tareas"]

def _norm(s: str) -> str:
    if s is None: return ""
    s = str(s).strip()
    s = unicodedata.normalize("NFD", s)
    s = "".join(ch for ch in s if unicodedata.category(ch) != "Mn")
    return s.lower()

def find_excel_path() -> str:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for name in EXCEL_CANDIDATES:
        p = os.path.join(repo_root, name)
        if os.path.exists(p):
            return p
    raise FileNotFoundError(f"No se encontró el Excel en la raíz. Busqué: {', '.join(EXCEL_CANDIDATES)}")

def pick_sheet_name(xls: pd.ExcelFile) -> str:
    names = [str(s) for s in xls.sheet_names]
    for pref in SHEET_PREFERENCE:
        for n in names:
            if _norm(n) == _norm(pref):
                return n
    return names[0]

def best_column_map(df: pd.DataFrame) -> dict:
    norm_cols = {_norm(c): c for c in df.columns}
    result = {}
    for final_key, aliases in HEADER_MAP.items():
        found = None
        for alias in aliases:
            if _norm(alias) in norm_cols:
                found = norm_cols[_norm(alias)]
                break
        if not found:
            for ncol, orig in norm_cols.items():
                if any(ncol.find(_norm(alias)) >= 0 for alias in aliases):
                    found = orig; break
        if found:
            result[final_key] = found
    return result

def to_iso_date(v):
    if pd.isna(v) or v == "": return None
    if isinstance(v, (datetime, date)):
        return datetime(v.year, v.month, v.day).date().isoformat()
    try:
        d = pd.to_datetime(v, dayfirst=True, errors="coerce")
        if pd.isna(d): return None
        return d.date().isoformat()
    except Exception:
        return None

def main():
    excel_path = find_excel_path()
    xls = pd.ExcelFile(excel_path, engine="openpyxl")
    sheet = pick_sheet_name(xls)

    # lee como texto, luego parsea fecha si corresponde
    df = xls.parse(sheet_name=sheet, dtype=str)
    df = df.loc[:, ~df.columns.astype(str).str.match(r"^Unnamed")]

    colmap = best_column_map(df)
    if "deadline" in colmap:
        df[colmap["deadline"]] = pd.to_datetime(df[colmap["deadline"]], dayfirst=True, errors="coerce")

    out_rows = []
    for _, row in df.iterrows():
        item = {
            "cliente":  str(row.get(colmap.get("cliente"), "")).strip(),
            "proyecto": str(row.get(colmap.get("proyecto"), "")).strip(),
            "tareas":   str(row.get(colmap.get("tareas"), "")).strip(),
            "estatus":  str(row.get(colmap.get("estatus"), "")).strip(),
            "owner":    str(row.get(colmap.get("owner"), "")).strip(),
            "email":    str(row.get(colmap.get("email"), "")).strip().lower(),
            "deadline": to_iso_date(row.get(colmap.get("deadline"), "")),
        }
        if any(item.values()):
            out_rows.append(item)

    # DEBUG visible en logs de Actions
    print(f"[info] Excel: {excel_path}")
    print(f"[info] Hoja usada: {sheet}")
    print(f"[info] Columnas: {list(df.columns)}")
    print(f"[info] Filas exportadas: {len(out_rows)}")

    out_path = os.path.abspath(OUTPUT_JSON)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out_rows, f, ensure_ascii=False, indent=2)

    print(f"[✓] Generado {out_path} con {len(out_rows)} filas")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("[x] Error en convert_excel_to_json.py:", e, file=sys.stderr)
        sys.exit(1)
