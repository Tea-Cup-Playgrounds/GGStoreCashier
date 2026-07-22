-- Migration: Add last_active_at column to users table
ALTER TABLE `users` 
ADD COLUMN `last_active_at` DATETIME NULL DEFAULT NULL AFTER `branch_id`;
