# scripts/convert_excel_to_json.py
import json
import os
import sys
import unicodedata
from datetime import datetime, date
import pandas as pd

# --- config ---
EXCEL_CANDIDATES = [
    "Template_Proyectos_Dashboard.xlsx",
    "Template_Proyectos_Dashboard.xlsm",
    "Template_Proyectos_Dashboard.xls",
]
OUTPUT_JSON = os.path.join(os.path.dirname(__file__), "..", "data.json")


def _norm(s: str) -> str:
    if s is None:
        return ""
    s = str(s).strip()
    s = unicodedata.normalize("NFD", s)
    s = "".join(ch for ch in s if unicodedata.category(ch) != "Mn")
    return s.lower()


# Mapa de encabezados flexibles -> clave final
HEADER_MAP = {
    "cliente": {"cliente", "account", "empresa"},
    "proyecto": {"proyecto", "project", "nombre proyecto"},
    "tareas": {"tareas", "tarea", "actividad", "actividad/tarea", "nombre tarea", "task"},
    "estatus": {"estatus", "estado", "status"},
    "owner": {"owner", "responsable", "asignado", "ejecutor"},
    "email": {"correo", "email", "owner email", "mail", "e-mail", "correo owner"},
    "deadline": {"deadline", "fecha limite", "fecha límite", "vencimiento", "due date"},
}

# Posibles nombres de hoja (si no, toma la primera)
SHEET_PREFERENCE = ["Proyectos", "Tareas"]


def find_excel_path() -> str:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for name in EXCEL_CANDIDATES:
        p = os.path.join(here, name)
        if os.path.exists(p):
            return p
    raise FileNotFoundError(
        f"No se encontró el Excel en la raíz. Busqué: {', '.join(EXCEL_CANDIDATES)}"
    )


def pick_sheet_name(xls: pd.ExcelFile) -> str:
    names = [str(s) for s in xls.sheet_names]
    # preferidos
    for pref in SHEET_PREFERENCE:
        for n in names:
            if _norm(n) == _norm(pref):
                return n
    # fallback: la primera
    return names[0]


def best_column_map(df: pd.DataFrame) -> dict:
    """Devuelve {clave_final -> nombre_columna_en_df} según HEADER_MAP"""
    norm_cols = {_norm(c): c for c in df.columns}
    result = {}
    for final_key, aliases in HEADER_MAP.items():
        found = None
        for alias in aliases:
            n = _norm(alias)
            if n in norm_cols:
                found = norm_cols[n]
                break
        # Si no lo encuentra exacto, prueba "contiene"
        if not found:
            for ncol, orig in norm_cols.items():
                if any(ncol.find(_norm(alias)) >= 0 for alias in aliases):
                    found = orig
                    break
        if found:
            result[final_key] = found
    return result


def to_iso_date(v):
    if pd.isna(v) or v == "":
        return None
    # Si viene como datetime/date ya
    if isinstance(v, (datetime, date)):
        return datetime(v.year, v.month, v.day).date().isoformat()
    # Intenta parsear con pandas
    try:
        d = pd.to_datetime(v, dayfirst=True, errors="coerce")
        if pd.isna(d):
            return None
        return d.date().isoformat()
    except Exception:
        return None


def main():
    excel_path = find_excel_path()
    xls = pd.ExcelFile(excel_path, engine="openpyxl")
    sheet = pick_sheet_name(xls)
    df = xls.parse(sheet_name=sheet, dtype=str)  # leemos todo como texto primero

    # Limpia columnas vacías “Unnamed”
    df = df.loc[:, ~df.columns.astype(str).str.match(r"^Unnamed")]

    colmap = best_column_map(df)
    required = {"cliente", "proyecto", "tareas", "estatus", "owner", "email", "deadline"}
    missing = [k for k in required if k not in colmap]
    # No abortamos por columnas faltantes: seguimos con lo disponible
    if missing:
        print(f"[!] Advertencia: no se encontraron columnas: {', '.join(missing)}", file=sys.stderr)

    # Relee con tipos automáticos para fechas si existe la columna deadline
    if "deadline" in colmap:
        # intenta parsear fechas directamente
        df[colmap["deadline"]] = pd.to_datetime(
            df[colmap["deadline"]], dayfirst=True, errors="coerce"
        )

    out_rows = []
    for _, row in df.iterrows():
        item = {}
        item["cliente"]  = str(row.get(colmap.get("cliente"), "")).strip()
        item["proyecto"] = str(row.get(colmap.get("proyecto"), "")).strip()
        item["tareas"]   = str(row.get(colmap.get("tareas"), "")).strip()
        item["estatus"]  = str(row.get(colmap.get("estatus"), "")).strip()
        item["owner"]    = str(row.get(colmap.get("owner"), "")).strip()
        email_val = str(row.get(colmap.get("email"), "")).strip()
        item["email"]    = email_val.lower()

        # fecha ISO (YYYY-MM-DD) o None
        dval = row.get(colmap.get("deadline"), "")
        item["deadline"] = to_iso_date(dval)

        # descarta filas completamente vacías
        if any(item.values()):
            out_rows.append(item)

    # aseguramos ruta
    out_path = os.path.abspath(OUTPUT_JSON)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out_rows, f, ensure_ascii=False, indent=2)

    print(f"[✓] Generado {out_path} con {len(out_rows)} filas (hoja: {sheet})")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("[x] Error en convert_excel_to_json.py:", e, file=sys.stderr)
        sys.exit(1)
