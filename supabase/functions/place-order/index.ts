// Server-only routing and transactional checkout. Never falls back to client pricing.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { googleKey, roadDistance } from './routing.ts';
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
const routingKeys=()=>({
 googleKey:googleKey([Deno.env.get('GOOGLE_MAPS_API_KEY'),Deno.env.get('GOOGLE_ROUTES_API_KEY')]),
 olaKey:Deno.env.get('OLA_MAPS_API_KEY')?.trim()||undefined,
});
Deno.serve(async req=>{
 if(req.method==='OPTIONS') return reply({});
 if(req.method!=='POST') return reply({error:'method_not_allowed'},405);
 try {
  const token=(req.headers.get('Authorization')??'').replace(/^Bearer /,'');
  if(new URL(req.url).searchParams.get('health')==='1'){
   if(!Deno.env.get('PUSH_WEBHOOK_TOKEN')||token!==Deno.env.get('PUSH_WEBHOOK_TOKEN')) return reply({error:'Unauthorized'},401);
   const d=await roadDistance({lat:28.8955,lng:76.6066},{lat:28.901,lng:76.58},routingKeys());
   return reply({routing_ready:d.provider!=='haversine',provider:d.provider,km:Number(d.km.toFixed(3))},d.provider!=='haversine'?200:503);
  }
  const url=Deno.env.get('SUPABASE_URL')!;
  const caller=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false},global:{headers:{Authorization:`Bearer ${token}`}}});
  const {data:{user},error:authError}=await caller.auth.getUser(token);
  if(authError||!user) return reply({error:'Sign in to continue'},401);
  const input=await req.json();
  const {vendor_id,dest_address,dest_lat,dest_lng,items,customer_note,quote_only,request_id,expected_total_paise}=input;
  if(typeof vendor_id!=='string'||typeof dest_address!=='string'||dest_address.trim().length<8||dest_address.length>1000||
   !Number.isFinite(dest_lat)||!Number.isFinite(dest_lng)||Math.abs(dest_lat)>90||Math.abs(dest_lng)>180||
   !Array.isArray(items)||items.length<1||items.length>100||
   (customer_note!=null&&(typeof customer_note!=='string'||customer_note.length>1000))) return reply({error:'Invalid checkout details'},400);
  if(!quote_only&&request_id!=null&&!/^[0-9a-f-]{36}$/i.test(request_id)) return reply({error:'Invalid request ID'},400);
  const service=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  // A retry after a lost response must work even if routing is temporarily offline.
  if(!quote_only&&request_id){
   const {data:prior}=await service.from('checkout_attempts').select('order_id').eq('customer_id',user.id).eq('request_id',request_id).maybeSingle();
   if(prior?.order_id){
    // RPC validates the original request fingerprint before returning the same order.
    const {data,error}=await service.rpc('mobile_place_order',{p_customer:user.id,p_request:request_id,p_vendor:vendor_id,p_address:dest_address.trim(),p_lat:dest_lat,p_lng:dest_lng,p_distance:0,p_items:items,p_note:customer_note??null,p_expected:expected_total_paise??null});
    return error?reply({error:error.message},400):reply({order_id:data});
   }
  }
  const {data:v,error:vError}=await caller.from('vendors').select('latitude,longitude,is_active,service_radius_km').eq('id',vendor_id).single();
  if(vError||!v?.is_active) return reply({error:'Store unavailable'},400);
  const {km,provider}=await roadDistance({lat:Number(v.latitude),lng:Number(v.longitude)},{lat:dest_lat,lng:dest_lng},routingKeys());
  if(km>Number(v.service_radius_km)) return reply({error:'Address is outside this store’s delivery area'},422);
  if(quote_only){
   const {data,error}=await service.rpc('resolve_checkout',{p_vendor_id:vendor_id,p_items:items,p_distance:km});
   return error?reply({error:error.message},400):reply({...data,distance_km:km,provider});
  }
  const {data,error}=await service.rpc('mobile_place_order',{p_customer:user.id,p_request:request_id??crypto.randomUUID(),p_vendor:vendor_id,p_address:dest_address.trim(),p_lat:dest_lat,p_lng:dest_lng,p_distance:km,p_items:items,p_note:customer_note??null,p_expected:expected_total_paise??null});
  return error?reply({error:error.message},400):reply({order_id:data,distance_km:km,provider});
 }catch(error){return reply({error:'Checkout temporarily unavailable. Retry the same attempt.', ...(new URL(req.url).searchParams.get('health')==='1'?{failure_type:error instanceof Error?error.name:'Unknown', failure_category:error instanceof Error?(/header|ByteString|character/i.test(error.message)?'invalid_header':/fetch|connect|dns/i.test(error.message)?'network':/AbortSignal|timeout/i.test(error.message)?'timeout_api':'other'):'other'}:{})},503);}
});
