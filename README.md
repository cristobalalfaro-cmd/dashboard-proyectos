# Dashboard de Proyectos

Sitio estático (GitHub Pages) + automatizaciones para:
- Convertir el Excel `Template_Proyectos_Dashboard.xlsx` a `data.json` (local o en CI).
- Mostrar un dashboard filtrable.
- Enviar alertas por correo de tareas vencidas o próximas a vencer, agrupadas por Owner y Proyecto.

## Estructura
```
dashboard-proyectos/
├─ .github/workflows/
│  ├─ deploy.yml
│  ├─ update-dashboard.yml
│  └─ deadline-alerts.yml
├─ icons/           # favicons / manifest icons
├─ scripts/         # utilidades (Python + JS) y automatización
├─ index.html       # app
├─ styles.css
├─ service-worker.js
├─ manifest.json
├─ settings.json
├─ Template_Proyectos_Dashboard.xlsx
├─ package.json
├─ actualizar.bat   # Windows: convierte y publica
└─ .env.example     # ejemplo de variables SMTP locales
```

## Variables para alertas (SMTP)
Crea un archivo `.env` en la raíz (no se sube al repo) con:
```
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=tu-correo@gmail.com
SMTP_PASSWORD=tu-app-password
ALERT_TO= # opcional: para pruebas forzar destinatario único
```
En GitHub Actions, guarda estos valores como *Secrets*.

## Ejecutar local
1) Windows: doble click a `actualizar.bat`. Genera `data.json` y hace push.
2) O manual:
   ```bash
   python -m venv .venv
   .venv\Scripts\python -m pip install -U pip pandas openpyxl
   .venv\Scripts\python scripts/convert_excel_to_json.py
   ```

## Publicar a GitHub Pages
El workflow `deploy.yml` despliega automáticamente al hacer push a `main`.
