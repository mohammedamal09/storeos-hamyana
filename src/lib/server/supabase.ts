import { createClient } from "@supabase/supabase-js";
export function env(){const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,secret=process.env.SUPABASE_SECRET_KEY;if(!url||!key||!secret)throw new Error("StoreOS is not connected to Supabase yet");return{url,key,secret}}
export function adminClient(){const e=env();return createClient(e.url,e.secret,{auth:{persistSession:false,autoRefreshToken:false}})}
export function publicClient(){const e=env();return createClient(e.url,e.key,{auth:{persistSession:false,autoRefreshToken:false}})}
