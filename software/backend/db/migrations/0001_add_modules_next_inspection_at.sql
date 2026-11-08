-- 0001_add_modules_next_inspection_at.sql
-- Adiciona a coluna para armazenar o agendamento da próxima inspeção reportada pelo ESP32
ALTER TABLE modules ADD COLUMN IF NOT EXISTS next_inspection_at timestamptz;
