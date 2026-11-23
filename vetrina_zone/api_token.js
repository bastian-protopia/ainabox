// AINABOX — Local Portable Sovereign AI
// Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
// Licensed under GPL-3.0-or-later

async function apiFetch(url,options){let t=localStorage.getItem("vetrina_token");if(!t){t=prompt("Token AINABOX:");if(t)localStorage.setItem("vetrina_token",t)}if(options&&options.headers){options.headers["Authorization"]="Bearer "+t}else if(options){options.headers={"Authorization":"Bearer "+t}}else{options={headers:{"Authorization":"Bearer "+t}}}return fetch(url,options)}
