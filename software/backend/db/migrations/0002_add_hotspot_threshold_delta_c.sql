-- 0002_add_hotspot_threshold_delta_c.sql
-- Adiciona o limiar de temperatura diferencial de hotspot configurável por módulo
ALTER TABLE modules 
ADD COLUMN IF NOT EXISTS hotspot_threshold_delta_c numeric(5,2) NOT NULL DEFAULT 8.0 
CHECK (hotspot_threshold_delta_c > 0 AND hotspot_threshold_delta_c <= 50.0);
