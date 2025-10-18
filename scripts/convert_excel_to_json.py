import json, os, pandas as pd
from datetime import datetime

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXCEL = os.path.join(BASE, "Template_Proyectos_Dashboard.xlsx")
JSON_OUT = os.path.join(BASE, "data.json")

if not os.path.exists(EXCEL):
    # Try also under scripts/data/ (optional)
    alt = os.path.join(BASE, "scripts", "data", "Template_Proyectos_Dashboard.xlsx")
    if os.path.exists(alt):
        EXCEL = alt
    else:
        print(f"[x] No pude encontrar el Excel: {EXCEL}")
        raise SystemExit(1)

print(f"[*] Leyendo Excel: {EXCEL}")
xls = pd.ExcelFile(EXCEL)

# Preferimos hoja "Proyectos" o "Tareas"
sheet = "Proyectos"
if sheet not in xls.sheet_names:
    sheet = "Tareas" if "Tareas" in xls.sheet_names else xls.sheet_names[0]

df = pd.read_excel(EXCEL, sheet_name=sheet)

# Normalizar columnas esperadas
aliases = {
    "cliente": ["Cliente","Account","Empresa"],
    "proyecto": ["Proyecto","Project","Nombre Proyecto"],
    "tareas": ["Tareas","Tarea","Actividad","Nombre Tarea","Task","Actividad/Tarea"],
    "tipo": ["Tipo","Category","Categoría"],
    "estatus": ["Estatus","Estado","Status"],
    "owner": ["Owner","Responsable","Asignado","Ejecutor"],
    "email": ["Correo","Email","Owner Email","Mail","e-mail","Correo Owner"],
    "deadline": ["Deadline","Fecha Limite","Fecha Límite","Vencimiento","Due Date"],
}
def pick(row, key):
    for a in aliases[key]:
        if a in row: return row[a]
    return None

records = []
for _, row in df.iterrows():
    r = {
        "cliente": pick(df, "cliente")[_] if isinstance(pick(df,"cliente"), pd.Series) else row.get("Cliente",""),
    }
# The above approach is error-prone; do a safer mapping:
records = []
for _, row in df.iterrows():
    def getval(keys):
        for k in keys:
            if k in df.columns: 
                return row.get(k, "")
        return ""
    def to_iso(v):
        if pd.isna(v) or v=="" :
            return None
        # Date-like to iso string yyyy-mm-dd
        if isinstance(v, (pd.Timestamp, datetime)):
            return v.strftime("%Y-%m-%d")
        try:
            # Excel serial?
            if isinstance(v,(int,float)) and v>20000:
                dt = pd.to_datetime("1899-12-30") + pd.to_timedelta(int(v),"D")
                return dt.strftime("%Y-%m-%d")
            dt = pd.to_datetime(v, dayfirst=True, errors="coerce")
            if pd.isna(dt): return None
            return dt.strftime("%Y-%m-%d")
        except Exception:
            return None

    rec = {
        "cliente":   getval(aliases["cliente"]),
        "proyecto":  getval(aliases["proyecto"]),
        "tareas":    getval(aliases["tareas"]),
        "tipo":      getval(aliases["tipo"]),
        "estatus":   getval(aliases["estatus"]),
        "owner":     getval(aliases["owner"]),
        "email":     getval(aliases["email"]),
        "deadline":  to_iso(getval(aliases["deadline"])),
    }
    # Filtrar filas vacías
    if any(str(rec[k]).strip() for k in ["cliente","proyecto","tareas","estatus","owner","deadline"]):
        records.append(rec)

with open(JSON_OUT, "w", encoding="utf-8") as f:
    json.dump(records, f, ensure_ascii=False, indent=2)

print(f"[✓] Generado {JSON_OUT} con {len(records)} filas (hoja: {sheet})")
