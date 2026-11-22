import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
export function cn(...inputs: ClassValue[]) { return twMerge(clsx(inputs)); }
export const money = (minor: number, locale = "en-MA") => new Intl.NumberFormat(locale, { style: "currency", currency: "MAD", minimumFractionDigits: 2 }).format(minor / 100);
export const dateTime = (value: string, locale = "en-GB") => new Intl.DateTimeFormat(locale, { timeZone: "Africa/Casablanca", dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
export const uuid = () => crypto.randomUUID();

