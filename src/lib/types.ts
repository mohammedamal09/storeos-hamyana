export type Role = "admin" | "cashier"; export type PaymentMethod = "cash" | "card"; export type SyncState = "online" | "offline" | "syncing" | "attention";
export interface Staff { id:string; name:string; role:Role; active:boolean }
export interface Category { id:string; name:string; archived_at?:string|null }
export interface Product { id:string; barcode:string; name:string; category_id:string|null; category_name?:string; cost_minor:number; price_minor:number; stock_qty:number; version_id:string; archived_at?:string|null }
export interface CartItem extends Product { qty:number }
export interface Shift { id:string; user_id:string; opened_at:string; closed_at:string|null; opening_cash_minor:number; expected_cash_minor:number|null; actual_cash_minor:number|null; difference_minor:number|null; status:"open"|"closed"; offline_authorized_until:string; pending?:boolean }
export interface SaleItem { product_id:string; product_name:string; version_id:string; qty:number; unit_price_minor:number; unit_cost_minor:number }
export interface Receipt { id:string; operation_id:string; reference:string; shift_id:string; user_id:string; cashier_name:string; items:SaleItem[]; total_minor:number; payment_method:PaymentMethod; tendered_minor?:number; change_minor?:number; occurred_at:string; pending:boolean; reversed_at?:string|null }
export interface DashboardData { revenue:{today:number;week:number;month:number}; profit:{today:number;week:number;month:number}; earnings:{today:number;week:number;month:number}; low_stock:Product[]; recent_sales:Receipt[]; shifts:Shift[] }
export interface QueueOperation { id:string; sequence:number; type:"sale"|"close_shift"; payload:unknown; status:"pending"|"failed"; created_at:string; error?:string }

