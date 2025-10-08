// scripts/check-deadlines.js
import fs from "fs";
import path from "path";
import XLSX from "xlsx";
import dayjs from "dayjs";
import nodemailer from "nodemailer";

// === Config ===
const EXCEL_FILE = "Template_Proyectos_Dashboard.xlsx";
const SHEET_NAME = "Tareas"; // si no existe, se usa la primera hoja
const ALERT_DAYS = 5;

// Mapeo flexible de encabezados
const FIELD_MAP = {
  cliente:  ["Cliente","Account","Empresa"],
  proyecto: ["Proyecto","Nombre Proyecto","Project"],
  tareas:   ["Tareas","Tarea","Actividad","Nombre Tarea","Task","Actividad/Tarea"],
  estatus:  ["Estatus","Estado","Status"],
  owner:    ["Owner","Responsable","Asignado","Ejecutor"],
  email:    ["Email","Correo","Mail"],
  deadline: ["Deadline","Fecha Limite","Fecha Límite","Vencimiento","Due Date"]
};

const norm = s => (s ?? "").toString().trim();
const normalizeKey = s => norm(s).normalize("NFD").replace(/[\u0300-\u036f]/g,"").toLowerCase();

function pick(row, aliases){
  for (const a of aliases) if (a in row) return row[a];
  return undefined;
}

// Parse de fechas: Excel serial, DD-MM-YYYY, DD/MM/YYYY, etc.
function toDate(v){
  if (v === undefined || v === null || v === "") return null;
  if (typeof v === "number"){
    const start = new Date(Date.UTC(1899,11,30));
    const d = new Date(start.getTime() + v*86400000);
    d.setHours(0,0,0,0);
    return d;
  }
  if (typeof v === "string"){
    const s = v.trim().replace(/[./]/g,"-");
    const m = s.match(/^(\d{1,2})-(\d{1,2})-(\d{2}|\d{4})/);
    if (m){
      let d = +m[1], mo = +m[2], y = +m[3];
      if (y < 100) y += 2000;
      const dt = new Date(y, mo-1, d);
      dt.setHours(0,0,0,0);
      if (!isNaN(dt)) return dt;
    }
    const dt2 = new Date(s);
    if (!isNaN(dt2)){ dt2.setHours(0,0,0,0); return dt2; }
  }
  if (v instanceof Date && !isNaN(v)) {
    const d = new Date(v.getTime());
    d.setHours(0,0,0,0);
    return d;
  }
  return null;
}

function isFinalizado(txt){
  const t = normalizeKey(txt);
  return (
    t === "finalizado" || t === "finalizada" ||
    t === "cerrado" || t === "completado" || t === "completada"
  );
}

// === Cargar Excel ===
const buf = fs.readFileSync(path.join(process.cwd(), EXCEL_FILE));
const wb  = XLSX.read(buf, {type:"buffer"});
const sheetName = wb.SheetNames.includes(SHEET_NAME) ? SHEET_NAME : wb.SheetNames[0];
const sheet = wb.Sheets[sheetName];
const rows = XLSX.utils.sheet_to_json(sheet, {defval:""});

// Normalizar filas a un objeto uniforme
const data = rows.map(r => {
  const deadline = toDate(pick(r, FIELD_MAP.deadline));
  return {
    cliente:  norm(pick(r, FIELD_MAP.cliente)),
    proyecto: norm(pick(r, FIELD_MAP.proyecto)),
    tareas:   norm(pick(r, FIELD_MAP.tareas)),
    estatus:  norm(pick(r, FIELD_MAP.estatus)),
    owner:    norm(pick(r, FIELD_MAP.owner)),
    email:    norm(pick(r, FIELD_MAP.email)),
    deadline,
  };
});

// === Particionar: próximas (0..ALERT_DAYS) vs. vencidas (<0), siempre NO finalizadas ===
const today = dayjs().startOf("day");

const proximas = [];
const vencidas = [];

for (const row of data) {
  if (!row.deadline) continue;
  if (isFinalizado(row.estatus)) continue;
  const d = dayjs(row.deadline).startOf("day");
  const diff = d.diff(today, "day");
  if (diff >= 0 && diff <= ALERT_DAYS) proximas.push(row);
  else if (diff < 0) vencidas.push(row);
}

// Si no hay nada que alertar, salir
if (proximas.length === 0 && vencidas.length === 0) {
  console.log("No hay tareas próximas a vencer ni vencidas pendientes.");
  process.exit(0);
}

// === Agrupar por correo para cada categoría ===
const groupByEmail = (rows) => {
  const map = new Map();
  for (const r of rows) {
    const key = r.email || ""; // si falta email, lo mandaremos al DEFAULT_TO
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(r);
  }
  return map;
};

const gProximas = groupByEmail(proximas);
const gVencidas = groupByEmail(vencidas);

// === SMTP con secretos de Actions ===
const smtpHost = process.env.SMTP_SERVER;
const smtpPort = Number(process.env.SMTP_PORT || 587);
const smtpUser = process.env.SMTP_USERNAME;
const smtpPass = process.env.SMTP_PASSWORD;
const DEFAULT_TO = process.env.ALERT_TO || ""; // para filas sin email

if (!smtpHost || !smtpUser || !smtpPass) {
  console.error("Faltan variables SMTP_SERVER / SMTP_USERNAME / SMTP_PASSWORD");
  process.exit(1);
}

const transporter = nodemailer.createTransport({
  host: smtpHost,
  port: smtpPort,
  secure: smtpPort === 465, // 465 SSL, 587/25 STARTTLS
  auth: { user: smtpUser, pass: smtpPass }
});

function makeTable(rows){
  const rowsHtml = rows.map(r => {
    const f = dayjs(r.deadline).format("DD-MM-YYYY");
    return `<tr>
      <td>${r.cliente}</td>
      <td>${r.proyecto}</td>
      <td>${r.tareas}</td>
      <td>${r.estatus}</td>
      <td>${r.owner}</td>
      <td>${f}</td>
    </tr>`;
  }).join("");

  return `
    <table cellpadding="6" cellspacing="0" border="1" style="border-collapse:collapse">
      <thead style="background:#f2f2f2">
        <tr>
          <th>Cliente</th><th>Proyecto</th><th>Tareas</th><th>Estatus</th><th>Owner</th><th>Deadline</th>
        </tr>
      </thead>
      <tbody>${rowsHtml}</tbody>
    </table>`;
}

function wrapHtml(header, rows){
  return `
  <div style="font-family:system-ui,Segoe UI,Roboto">
    <h2>${header}</h2>
    ${makeTable(rows)}
    <p style="margin-top:10px">Ver dashboard: <a href="https://cristobalalfaro-cmd.github.io/dashboard-proyectos/">Link</a></p>
  </div>`;
}

async function sendBatch(groups, subject, header){
  let sent = 0;

  // 1) A los que tienen email propio
  for (const [to, rows] of groups.entries()) {
    if (!to) continue;
    const html = wrapHtml(header, rows);
    await transporter.sendMail({
      from: `"Alertas Dashboard" <${smtpUser}>`,
      to,
      subject,
      html
    });
    sent++;
    console.log(`OK enviado a ${to} (${rows.length} tareas).`);
  }

  // 2) Filas sin email → AL DEFAULT_TO (si está configurado)
  const missing = groups.get("") || [];
  if (missing.length && DEFAULT_TO) {
    const html = wrapHtml(header, missing);
    await transporter.sendMail({
      from: `"Alertas Dashboard" <${smtpUser}>`,
      to: DEFAULT_TO, // admite lista coma-separada
      subject,
      html
    });
    sent++;
    console.log(`OK enviado resumen sin email a ${DEFAULT_TO} (${missing.length} tareas).`);
  }

  return sent;
}

(async () => {
  let total = 0;

  // A) Próximas a vencer (0..5 días)
  if (proximas.length) {
    const subject = "Faltan 5 días o menos para completar tareas pendientes";
    const header  = "Faltan 5 días o menos para completar las siguientes tareas pendientes";
    total += await sendBatch(gProximas, subject, header);
  }

  // B) Vencidas
  if (vencidas.length) {
    const subject = "Tienes tareas vencidas y urgentes por completar";
    const header  = "Tienes tareas vencidas y urgentes por completar";
    total += await sendBatch(gVencidas, subject, header);
  }

  console.log(`Listo: ${total} correo(s) enviados.`);
})().catch(err => {
  console.error("Error enviando correos:", err);
  process.exit(1);
});