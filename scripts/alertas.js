// Envío de recordatorios leyendo data.json (generado por build-data.yml)
try { require('dotenv').config(); } catch (_) {}

const fs = require('fs');
const path = require('path');
const nodemailer = require('nodemailer');

const DATA_JSON = path.resolve(__dirname, '..', 'data.json');
const DASH_BASE = 'https://cristobalalfaro-cmd.github.io/dashboard-proyectos/';

const {
  SMTP_SERVER,
  SMTP_PORT,
  SMTP_USERNAME,
  SMTP_PASSWORD,
  ALERT_TO,
  ONLY_EMAIL,   // pruebas: enviar sólo a este correo
  ONLY_PROJECT  // pruebas: filtrar por nombre de proyecto
} = process.env;

const DRY = process.argv.includes('--dry-run');

function norm(s){ return (s ?? '').toString().trim(); }
function nkey(s){ return norm(s).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase(); }
function toDate(v){
  if (!v) return null;
  const d = new Date(v);
  return isNaN(d) ? null : new Date(d.getFullYear(), d.getMonth(), d.getDate());
}
function isDone(s){
  const t = nkey(s);
  return ['finalizado','finalizada','cerrado','completado','completada'].includes(t);
}

function readDataJson(){
  if (!fs.existsSync(DATA_JSON)) {
    throw new Error('No existe data.json. Asegúrate de que la Action "Build data.json" haya corrido.');
  }
  const raw = JSON.parse(fs.readFileSync(DATA_JSON, 'utf8'));

  // Adapta a tu estructura exacta de data.json si fuera distinto
  // Suponemos un array de filas con estas llaves estándar:
  // { cliente, proyecto, tareas, estatus, owner, email, deadline }
  return raw.map(r => ({
    cliente: norm(r.cliente ?? r.Cliente ?? r.Account ?? ''),
    proyecto: norm(r.proyecto ?? r.Proyecto ?? r.Project ?? ''),
    tareas:   norm(r.tareas   ?? r.Tareas   ?? r.Tarea   ?? r.Actividad ?? ''),
    estatus:  norm(r.estatus  ?? r.Estatus  ?? r.Estado  ?? r.Status    ?? ''),
    owner:    norm(r.owner    ?? r.Owner    ?? r.Responsable ?? ''),
    email:    norm((r.email   ?? r.Correo   ?? r.Email   ?? r['Owner Email'] ?? '').toLowerCase()),
    deadline: toDate(r.deadline ?? r.Deadline ?? r['Fecha Limite'] ?? r['Fecha Límite'] ?? r['Due Date'] ?? '')
  }));
}

function splitTasks(rows){
  const today = new Date(); today.setHours(0,0,0,0);
  const FIVE = 5*86400000;
  const vencidas=[], proximas=[];
  for (const r of rows){
    if (isDone(r.estatus)) continue;
    if (!r.deadline) continue;
    const ts = r.deadline.getTime();
    if (ts < today.getTime()) vencidas.push(r);
    else if (ts - today.getTime() <= FIVE) proximas.push(r);
  }
  return { vencidas, proximas };
}

function groupByEmailProject(rows){
  const map = new Map();
  for (const r of rows){
    const email = (r.email||'').toLowerCase();
    if (!email) continue;
    if (ONLY_EMAIL && email !== ONLY_EMAIL.toLowerCase()) continue;

    const proj = r.proyecto || '(sin proyecto)';
    if (ONLY_PROJECT && proj !== ONLY_PROJECT) continue;

    const key = email + '|||' + proj;
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(r);
  }
  return map;
}

function fmtDate(d){ return d ? d.toLocaleDateString('es-CL') : ''; }

function renderTable(title, rows){
  if (!rows.length) return '';
  const head = `
    <h3 style="margin:16px 0 8px 0">${title}</h3>
    <table border="0" cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:100%;max-width:900px">
      <thead>
        <tr style="background:#f5f5f5">
          <th align="left">Cliente</th>
          <th align="left">Proyecto</th>
          <th align="left">Tareas</th>
          <th align="left">Estatus</th>
          <th align="left">Owner</th>
          <th align="left">Deadline</th>
        </tr>
      </thead><tbody>`;
  const body = rows.map(r=>`
    <tr style="border-bottom:1px solid #eee">
      <td>${r.cliente||''}</td>
      <td>${r.proyecto||''}</td>
      <td>${r.tareas||''}</td>
      <td>${r.estatus||''}</td>
      <td>${r.owner||''}</td>
      <td>${fmtDate(r.deadline)||''}</td>
    </tr>`).join('');
  return head + body + '</tbody></table>';
}

function emailHTML({cliente, proyecto, vencidas, proximas}){
  const dash = `${DASH_BASE}?cliente=${encodeURIComponent(cliente||'')}`;
  const intro = `
    <p style="margin:0 0 12px 0">
      Hola! éste es un recordatorio generado automáticamente para que aseguremos el avance del proyecto de acuerdo a la planificación acordada.
      Favor si necesitas contactarme lo puedes hacer respondiendo este correo o a mi WS directo <strong>+56996420469</strong>.
      <br/>Saludos cordiales, <strong>Cristóbal Alfaro</strong>.
    </p>`;
  const btn = `
    <p style="margin:16px 0 8px 0">
      <a href="${dash}" style="display:inline-block;background:#111;color:#fff;text-decoration:none;padding:10px 14px;border-radius:8px;font-weight:600">Ver dashboard</a>
    </p>`;
  let html = `<div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Arial;max-width:920px">
    <h2 style="margin:0 0 6px 0">Proyecto ${proyecto}: Tienes tareas asignadas vencidas o próximas a vencer</h2>
    ${intro}
    ${btn}`;
  html += renderTable("Tareas vencidas", vencidas);
  html += renderTable("Tareas próximas a vencer (≤ 5 días)", proximas);
  if (!vencidas.length && !proximas.length){
    html += `<p>No hay tareas vencidas ni próximas a vencer.</p>`;
  }
  html += `</div>`;
  return html;
}

async function transport(){
  if (DRY){
    return { sendMail: async (o)=>{
      console.log("\n--- DRY RUN ---");
      console.log("TO:", o.to);
      console.log("SUBJECT:", o.subject);
      return { messageId:"(dry)" };
    }};
  }
  if(!SMTP_SERVER || !SMTP_PORT || !SMTP_USERNAME || !SMTP_PASSWORD){
    throw new Error("Faltan variables SMTP_* en el entorno.");
  }
  return require('nodemailer').createTransport({
    host: SMTP_SERVER,
    port: Number(SMTP_PORT),
    secure: Number(SMTP_PORT)===465,
    auth: { user: SMTP_USERNAME, pass: SMTP_PASSWORD },
  });
}

(async function main(){
  try{
    const all = readDataJson();
    const groups = groupByEmailProject(all);
    const t = await transport();
    let sent=0;

    for (const [key, rows] of groups.entries()){
      const [email, proyecto] = key.split('|||');
      const { vencidas, proximas } = splitTasks(rows);
      if (!vencidas.length && !proximas.length) continue;

      // cliente predominante para el link
      const byC = {}; rows.forEach(r=>{ const c=r.cliente||''; byC[c]=(byC[c]||0)+1; });
      const cliente = Object.entries(byC).sort((a,b)=>b[1]-a[1])[0]?.[0] || '';

      const to = ALERT_TO || email;
      const subject = `Proyecto ${proyecto}: Tienes tareas asignadas vencidas o próximas a vencer`;
      const html = emailHTML({ cliente, proyecto, vencidas, proximas });

      const info = await t.sendMail({
        from: `"PMO Cristóbal Alfaro" <${SMTP_USERNAME}>`,
        to, subject, html
      });
      sent++; console.log(`✔ Enviado a ${to} (proyecto=${proyecto}) id=${info.messageId}`);
    }
    if (sent===0) console.log("No había tareas para alertar.");
  }catch(err){
    console.error("✖ Error enviando alertas:", err);
    process.exit(1);
  }
})();
