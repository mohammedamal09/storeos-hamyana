export class ApiError extends Error{constructor(message:string,public status:number,public details?:unknown){super(message)}}
export async function api<T>(url:string,init?:RequestInit):Promise<T>{const response=await fetch(url,{...init,headers:{"Content-Type":"application/json",...(init?.headers||{})},cache:"no-store"});let body:unknown;try{body=await response.json()}catch{body={}}if(!response.ok){const b=body as {error?:string};throw new ApiError(b.error||"Request failed",response.status,body)}return body as T}

