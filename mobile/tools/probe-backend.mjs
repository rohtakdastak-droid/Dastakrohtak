import {readFile} from 'node:fs/promises';
const config=JSON.parse((await readFile(new URL('../config/local.json',import.meta.url),'utf8')).replace(/^\uFEFF/,''));
for(const path of ['rest/v1/vendors?select=id,name,category&limit=1','rest/v1/products?select=id,stock&limit=1','rest/v1/checkout_attempts?select=request_id&limit=1']){
 try{const response=await fetch(`${config.SUPABASE_URL}/${path}`,{headers:{apikey:config.SUPABASE_ANON_KEY,Authorization:`Bearer ${config.SUPABASE_ANON_KEY}`},signal:AbortSignal.timeout(12000)});
 const body=await response.json();console.log(JSON.stringify({resource:path.split('?')[0],status:response.status,rows:Array.isArray(body)?body.length:undefined,code:body.code}));
 }catch{console.log(JSON.stringify({resource:path.split('?')[0],error:'Connection failed'}));}
}
