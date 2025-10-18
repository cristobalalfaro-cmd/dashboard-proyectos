// Envío de recordatorios agrupando por (OwnerEmail, Proyecto)
try{ require('dotenv').config(); }catch(_){}

const fs = require('fs');
const path = require('path');
const XLSX = require('xlsx');
const nodemailer = require('nodemailer');

const EXCEL = path.resolve(__dirname, '..', 'Template_Proyectos_Dashboard.xlsx');
const DASH_BASE = 'https://cristobalalfaro-cmd.github.io/dashboard-proyectos/';

const {
  SMTP_SERVER,
  SMTP_PORT,
  SMTP_USERNAME,
  SMTP_PASSWORD,
  ALERT_TO,
  ONLY_EMAIL,     // pruebas: enviar sólo a este correo
  ONLY_PROJECT    // pruebas: filtrar por nombre de proyecto
} = process.env;

const DRY = process.argv.includes('--dry-run');

function norm(s){ return (s??'').toString().trim(); }
function nkey(s){ return norm(s).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase(); }
function toDate(v){
  if(!v) return null;
  const d = new Date(v); return isNaN(d)? null : new Date(d.getFullYear(), d.getMonth(), d.getDate());
}
function isDone(s){
  const t = nkey(s);
  return ['finalizado','finalizada','cerrado','completado','completada'].includes(t);
}

function readExcel(){
  if(!fs.existsSync(EXCEL)) throw new Error('No se encontró el Excel en: '+EXCEL);
  const wb = XLSX.readFile(EXCEL);
  const sheet = wb.SheetNames.includes('Tareas') ? 'Tareas' : (wb.SheetNames.includes('Proyectos')?'Proyectos':wb.SheetNames[0]);
  const rows = XLSX.utils.sheet_to_json(wb.Sheets[sheet], {defval:''});
  const map = {
    cliente:['Cliente','Account','Empresa'],
    proyecto:['Proyecto','Project','Nombre Proyecto'],
    tareas:['Tareas','Tarea','Actividad','Nombre Tarea','Task','Actividad/Tarea'],
    estatus:['Estatus','Estado','Status'],
    deadline:['Deadline','Fecha Limite','Fecha Límite','Vencimiento','Due Date'],
    owner:['Owner','Responsable','Asignado','Ejecutor'],
    email:['Correo','Email','Owner Email','Mail','e-mail','Correo Owner'],
  };
  function pick(r, keys){ for(const k of keys){ if(k in r) return r[k]; } return ''; }
  return rows.map(r=>({
    cliente: norm(pick(r,map.cliente)),
    proyecto: norm(pick(r,map.proyecto)),
    tareas: norm(pick(r,map.tareas)),
    estatus: norm(pick(r,map.estatus)),
    owner: norm(pick(r,map.owner)),
    email: norm(pick(r,map.email)),
    deadline: toDate(pick(r,map.deadline))
  }));
}

function splitTasks(rows){
  const today = new Date(); today.setHours(0,0,0,0);
  const FIVE = 5*86400000;
  const vencidas=[], proximas=[];
  for(const r of rows){
    if(isDone(r.estatus)) continue;
    if(!r.deadline) continue;
    const ts = r.deadline.getTime();
    if(ts < today.getTime()) vencidas.push(r);
    else if(ts - today.getTime() <= FIVE) proximas.push(r);
  }
  return {vencidas, proximas};
}

function groupByEmailProject(rows){
  const map = new Map();
  for(const r of rows){
    const email = (r.email||'').toLowerCase();
    if(!email) continue;
    if(ONLY_EMAIL && email!==ONLY_EMAIL.toLowerCase()) continue;
    const proj = r.proyecto || '(sin proyecto)';
    if(ONLY_PROJECT && proj !== ONLY_PROJECT) continue;
    const key = email+'|||'+proj;
    if(!map.has(key)) map.set(key, []);
    map.get(key).push(r);
  }
  return map;
}

function fmtDate(d){ if(!d) return ''; return d.toLocaleDateString('es-CL'); }

function renderTable(title, rows){
  if(!rows.length) return '';
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
  if(!vencidas.length && !proximas.length){
    html += `<p>No hay tareas vencidas ni próximas a vencer.</p>`;
  }
  html += `</div>`;
  return html;
}

async function transport(){
  if(DRY){
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
  return nodemailer.createTransport({
    host: SMTP_SERVER,
    port: Number(SMTP_PORT),
    secure: Number(SMTP_PORT)===465,
    auth: { user: SMTP_USERNAME, pass: SMTP_PASSWORD },
  });
}

(async function main(){
  try{
    const all = readExcel();
    const groups = groupByEmailProject(all);
    const t = await transport();
    let sent=0;

    for(const [key, rows] of groups.entries()){
      const [email, proyecto] = key.split("|||");
      const {vencidas, proximas} = splitTasks(rows);
      if(!vencidas.length && !proximas.length) continue;
      // cliente dominante para el link
      const byC = {}; rows.forEach(r=>{ const c=r.cliente||''; byC[c]=(byC[c]||0)+1; });
      const cliente = Object.entries(byC).sort((a,b)=>b[1]-a[1])[0]?.[0] || "";
      const to = ALERT_TO || email;
      const subject = `Proyecto ${proyecto}: Tienes tareas asignadas vencidas o próximas a vencer`;
      const html = emailHTML({cliente, proyecto, vencidas, proximas});

      const info = await t.sendMail({
        from: `"PMO Cristóbal Alfaro" <${SMTP_USERNAME}>`,
        to, subject, html
      });
      sent++; console.log(`✔ Enviado a ${to} (proyecto=${proyecto}) id=${info.messageId}`);
    }
    if(sent===0) console.log("No había tareas para alertar.");
  }catch(err){
    console.error("✖ Error enviando alertas:", err);
    process.exit(1);
  }
})();
