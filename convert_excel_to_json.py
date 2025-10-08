# convert_excel_to_json.py
import json, sys, os
import pandas as pd

EXCEL = os.environ.get("DASH_EXCEL", "Template_Proyectos_Dashboard.xlsx")
JSON  = os.environ.get("DASH_JSON",  "data.json")

if not os.path.exists(EXCEL):
    print(f"[x] No encuentro el Excel: {EXCEL}")
    sys.exit(2)

# Lee la hoja "Tareas" si existe, si no la primera
xls = pd.ExcelFile(EXCEL)
sheet = "Tareas" if "Tareas" in xls.sheet_names else xls.sheet_names[0]
df = pd.read_excel(xls, sheet_name=sheet)

# Mantén solo las columnas esperadas si existen
cols = ["Tipo","Cliente","Proyecto","Tareas","Deadline","Estatus","Owner"]
df = df[[c for c in cols if c in df.columns]]

# Deadline → epoch ms (maneja fechas que vengan como número o texto)
def to_ts(v):
    if pd.isna(v): return None
    try:
        # Si ya viene en epoch ms (número grande), respétalo
        if isinstance(v, (int, float)) and v > 10_000_000_000:
            return int(v)
        return int(pd.to_datetime(v).timestamp() * 1000)
    except Exception:
        return None

if "Deadline" in df.columns:
    df["Deadline"] = df["Deadline"].apply(to_ts)

# Vacíos a string
for c in df.columns:
    df[c] = df[c].astype("object").where(pd.notna(df[c]), "")

records = df.to_dict(orient="records")

with open(JSON, "w", encoding="utf-8") as f:
    json.dump(records, f, ensure_ascii=False, indent=2)

print(f"[✓] Generado {JSON} con {len(records)} filas (hoja: {sheet})")