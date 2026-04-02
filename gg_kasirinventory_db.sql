-- phpMyAdmin SQL Dump
-- version 5.2.2
-- https://www.phpmyadmin.net/
--
-- Host: localhost:3306
-- Generation Time: Apr 02, 2026 at 12:21 AM
-- Server version: 8.0.30
-- PHP Version: 8.1.10

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `gg_kasir_db`
--

-- --------------------------------------------------------

--
-- Table structure for table `absensi`
--

CREATE TABLE `absensi` (
  `id` int NOT NULL,
  `absensi_image` varchar(30) NOT NULL,
  `kehadiran` enum('Hadir','Izin','Sakit','Tidak Masuk','Tanpa Keterangan') NOT NULL,
  `users_id` int NOT NULL,
  `branches_id` int NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- --------------------------------------------------------

--
-- Table structure for table `branches`
--

CREATE TABLE `branches` (
  `id` int NOT NULL,
  `name` varchar(100) NOT NULL,
  `address` text,
  `phone` varchar(20) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `branches`
--

INSERT INTO `branches` (`id`, `name`, `address`, `phone`, `created_at`, `updated_at`) VALUES
(0, 'Semua Branch', '0', '0', '2025-09-26 10:13:52', '2025-09-26 10:14:11'),
(1, 'Cabang Satu', 'Jalan Cabang Pertama, Samarinda Kota', '+62 85211223344', '2025-09-26 10:13:52', '2025-09-26 10:14:42'),
(2, 'Cabang Dua', 'Jalan Cabang Kedua, Samarinda Seberang', '+62 85222334455', '2025-09-26 10:13:52', '2025-09-26 10:14:42'),
(3, 'Cabang Tiga', 'Jalan Cabang Ketiga, Loa Janan', '+62 85233445566', '2025-09-26 10:13:52', '2025-09-26 10:14:42'),
(4, 'Cabang Empat', 'Jalan Cabang Keempat, Palaran', '+62 85244556677', '2025-09-26 10:13:52', '2025-09-26 10:14:42'),
(5, 'Cabang Lima', 'Jalan Cabang Kelima, Mangkupalas', '+62 85255667788', '2025-09-26 10:13:52', '2025-09-26 10:14:42');

-- --------------------------------------------------------

--
-- Table structure for table `categories`
--

CREATE TABLE `categories` (
  `id` int NOT NULL,
  `name` varchar(100) NOT NULL,
  `description` text,
  `category_image` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `categories`
--

INSERT INTO `categories` (`id`, `name`, `description`, `category_image`, `created_at`, `updated_at`) VALUES
(1, 'Kategori 1', 'Kategori 1', NULL, '2026-02-11 22:14:32', '2026-02-11 22:14:32'),
(2, 'Kategori 2', 'Kucing', 'category-1774950040066-629076979.jpg', '2026-03-31 17:40:40', '2026-03-31 17:40:40');

-- --------------------------------------------------------

--
-- Table structure for table `payments`
--

CREATE TABLE `payments` (
  `id` int NOT NULL,
  `transaction_id` int NOT NULL,
  `method` enum('cash','transfer','e-wallet','card') NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `payments`
--

INSERT INTO `payments` (`id`, `transaction_id`, `method`, `amount`, `created_at`) VALUES
(1, 1, 'cash', 50000.00, '2026-03-30 16:32:50'),
(2, 2, 'cash', 262000.00, '2026-03-30 18:45:27'),
(3, 3, 'cash', 50000.00, '2026-03-30 18:46:03'),
(4, 4, 'cash', 100000.00, '2026-03-30 18:47:33'),
(5, 5, 'cash', 600000.00, '2026-03-31 18:50:20');

-- --------------------------------------------------------

--
-- Table structure for table `products`
--

CREATE TABLE `products` (
  `id` int NOT NULL,
  `name` varchar(150) NOT NULL,
  `barcode` varchar(100) DEFAULT NULL,
  `category_id` int DEFAULT NULL,
  `sell_price` decimal(12,2) NOT NULL,
  `stock` int DEFAULT '0',
  `product_image` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
  `branch_id` int DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `products`
--

INSERT INTO `products` (`id`, `name`, `barcode`, `category_id`, `sell_price`, `stock`, `product_image`, `branch_id`, `created_at`, `updated_at`) VALUES
(1, 'Udin Din Din Dun Udin', 'GG1770897114723129', 1, 150000.00, 500, NULL, 3, '2026-02-12 19:51:54', '2026-02-12 19:51:54'),
(2, 'Charger', 'GG1774798551798876', 1, 25000.00, 500, NULL, 5, '2026-03-29 23:35:51', '2026-03-29 23:35:51'),
(3, 'om om gay', 'GG1774826357029221', 1, 50000.00, 6766, 'product-1774954410410-281737060.jpg', 5, '2026-03-30 07:19:17', '2026-03-31 18:53:30'),
(4, 'rio makan', 'GG177486667412243', 1, 1000.00, 6767, 'product-1774866671869-415634387.jpg', 0, '2026-03-30 18:31:14', '2026-03-30 18:39:09'),
(5, 'furab💜', 'GG1774866736588989', 1, 250000.00, 9, 'product-1774866736504-354269771.jpg', 2, '2026-03-30 18:32:16', '2026-03-30 18:45:27'),
(6, 'papa zola', 'GG1774866932561606', 1, 12000.00, 9, 'product-1774866927527-741001976.jpg', 1, '2026-03-30 18:35:32', '2026-03-30 18:45:27'),
(7, 'Bebek jenglot', 'GG1774866991975512', 1, 50000.00, 8, 'product-1774866990994-613055674.jpg', 2, '2026-03-30 18:36:31', '2026-03-30 18:47:33'),
(8, 'Katze', 'GG177494692939621', 1, 100000.00, 6766, 'product-1774946929232-746664353.jpg', 2, '2026-03-31 16:48:49', '2026-03-31 18:50:20'),
(9, 'tes camera 1', 'GG1774947567835438', 1, 500000.00, 5554, 'product-1774947567669-832536749.jpg', 4, '2026-03-31 16:59:27', '2026-03-31 18:50:20'),
(10, 'Tes Galeri', 'GG1774954119304267', 2, 50000.00, 2588, 'product-1774954119151-797486035.jpg', 5, '2026-03-31 18:48:39', '2026-03-31 18:48:39');

-- --------------------------------------------------------

--
-- Table structure for table `returns`
--

CREATE TABLE `returns` (
  `id` int NOT NULL,
  `transaction_id` int NOT NULL,
  `product_id` int NOT NULL,
  `qty` int NOT NULL,
  `reason` text,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- --------------------------------------------------------

--
-- Table structure for table `stock_movements`
--

CREATE TABLE `stock_movements` (
  `id` int NOT NULL,
  `product_id` int NOT NULL,
  `branch_id` int NOT NULL,
  `type` enum('in','out') NOT NULL,
  `qty` int NOT NULL,
  `note` text,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `stock_movements`
--

INSERT INTO `stock_movements` (`id`, `product_id`, `branch_id`, `type`, `qty`, `note`, `created_at`, `updated_at`) VALUES
(1, 3, 0, 'out', 1, 'Sale - Transaction #1', '2026-03-30 16:32:50', '2026-03-30 16:32:50'),
(2, 5, 2, 'out', 1, 'Sale - Transaction #2', '2026-03-30 18:45:27', '2026-03-30 18:45:27'),
(3, 6, 2, 'out', 1, 'Sale - Transaction #2', '2026-03-30 18:45:27', '2026-03-30 18:45:27'),
(4, 7, 2, 'out', 1, 'Sale - Transaction #3', '2026-03-30 18:46:03', '2026-03-30 18:46:03'),
(5, 7, 2, 'out', 2, 'Sale - Transaction #4', '2026-03-30 18:47:33', '2026-03-30 18:47:33'),
(6, 9, 4, 'out', 1, 'Sale - Transaction #5', '2026-03-31 18:50:20', '2026-03-31 18:50:20'),
(7, 8, 4, 'out', 1, 'Sale - Transaction #5', '2026-03-31 18:50:20', '2026-03-31 18:50:20');

-- --------------------------------------------------------

--
-- Table structure for table `transactions`
--

CREATE TABLE `transactions` (
  `id` int NOT NULL,
  `user_id` int NOT NULL,
  `branch_id` int NOT NULL,
  `total_amount` decimal(12,2) NOT NULL,
  `discount` decimal(12,2) DEFAULT '0.00',
  `final_amount` decimal(12,2) NOT NULL,
  `payment_status` enum('paid','unpaid','partial') NOT NULL DEFAULT 'unpaid',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `transactions`
--

INSERT INTO `transactions` (`id`, `user_id`, `branch_id`, `total_amount`, `discount`, `final_amount`, `payment_status`, `created_at`, `updated_at`) VALUES
(1, 1, 0, 50000.00, 0.00, 50000.00, 'paid', '2026-03-30 16:32:50', '2026-03-30 16:32:50'),
(2, 7, 2, 262000.00, 0.00, 262000.00, 'paid', '2026-03-30 18:45:27', '2026-03-30 18:45:27'),
(3, 7, 2, 50000.00, 0.00, 50000.00, 'paid', '2026-03-30 18:46:03', '2026-03-30 18:46:03'),
(4, 7, 2, 100000.00, 0.00, 100000.00, 'paid', '2026-03-30 18:47:33', '2026-03-30 18:47:33'),
(5, 1, 4, 600000.00, 0.00, 600000.00, 'paid', '2026-03-31 18:50:20', '2026-03-31 18:50:20');

-- --------------------------------------------------------

--
-- Table structure for table `transaction_items`
--

CREATE TABLE `transaction_items` (
  `id` int NOT NULL,
  `transaction_id` int NOT NULL,
  `product_id` int NOT NULL,
  `qty` int NOT NULL,
  `price` decimal(12,2) NOT NULL,
  `subtotal` decimal(12,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `transaction_items`
--

INSERT INTO `transaction_items` (`id`, `transaction_id`, `product_id`, `qty`, `price`, `subtotal`) VALUES
(1, 1, 3, 1, 50000.00, 50000.00),
(2, 2, 5, 1, 250000.00, 250000.00),
(3, 2, 6, 1, 12000.00, 12000.00),
(4, 3, 7, 1, 50000.00, 50000.00),
(5, 4, 7, 2, 50000.00, 100000.00),
(6, 5, 9, 1, 500000.00, 500000.00),
(7, 5, 8, 1, 100000.00, 100000.00);

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `id` int NOT NULL,
  `name` varchar(100) NOT NULL,
  `username` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
  `password` varchar(255) NOT NULL,
  `role` enum('karyawan','admin','superadmin') NOT NULL DEFAULT 'karyawan',
  `branch_id` int DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`id`, `name`, `username`, `password`, `role`, `branch_id`, `created_at`, `updated_at`) VALUES
(1, 'King Wahyu', 'superadmin', '$2b$12$P07jhhBCn0QnCyXHQRfYGOVIx/SW16WxSPfuajScCLErrr1vwxGny', 'superadmin', 0, '2025-09-26 11:04:07', '2026-02-06 10:49:48'),
(2, 'Boss Kebun', 'GrowAGarden#1', '$2b$12$kioin3Gy78nh3h/WC60n8uuI.fzQnhQe3J6BXM9kMHONobeej1U5.', 'admin', 1, '2025-09-26 11:04:07', '2026-02-03 15:47:52'),
(3, 'Boss Ikan', 'mancingmaniamantap', '$2b$12$MHPui3mOe1Me7TbjOTxtkO1uOi0twI0bFin2ITQAzpqE4zXoy7kuS', 'admin', 2, '2025-09-26 11:04:07', '2026-02-03 15:47:52'),
(4, 'Kroco 1', 'kroco1', '$2b$12$0pZIlcdAgmXOgpaM2jLYX.MMizLVAJDTwdsf3HZpG6qHTLHs8s8mu', 'karyawan', 1, '2025-09-26 11:04:07', '2026-02-03 15:47:53'),
(5, 'Kroco 2', 'kroco2', '$2b$12$UGJzu61DCfmxl.e8U9vRfuy0VVKH0n4i4iJWiCy9b/JtypulmcLza', 'karyawan', 2, '2025-09-26 11:04:07', '2026-02-03 15:47:53'),
(6, 'Karyawan Testing', 'karyawantesting1', '$2b$12$W3YaLIp4M2devPpicLbNYuSl97Vm3XG/kaQFZx6AhQTCZTnexu46K', 'karyawan', 1, '2026-02-06 10:52:23', '2026-02-06 16:29:42'),
(7, 'papa zola', 'PapaZola', '$2b$12$mIWpwRTT7HeiDNb6XaPgx.bOzuAKevDsZ5ekXuY/gGRg9CGYUi.Uq', 'karyawan', 2, '2026-03-30 18:41:56', '2026-03-30 18:43:58');

-- --------------------------------------------------------

--
-- Table structure for table `vouchers`
--

CREATE TABLE `vouchers` (
  `id` int NOT NULL,
  `code` varchar(50) NOT NULL,
  `description` text,
  `target_type` enum('categories','product') CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
  `target_id` bigint DEFAULT NULL,
  `discount_type` enum('percent','fixed') NOT NULL,
  `discount_value` decimal(12,2) NOT NULL,
  `valid_from` date DEFAULT NULL,
  `valid_to` date DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT '1'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `absensi`
--
ALTER TABLE `absensi`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_users_id` (`users_id`) USING BTREE,
  ADD KEY `idx_branches_id` (`branches_id`) USING BTREE;

--
-- Indexes for table `branches`
--
ALTER TABLE `branches`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `categories`
--
ALTER TABLE `categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `payments`
--
ALTER TABLE `payments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_payment_transaction` (`transaction_id`);

--
-- Indexes for table `products`
--
ALTER TABLE `products`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `barcode` (`barcode`),
  ADD KEY `idx_products_category` (`category_id`),
  ADD KEY `idx_products_branch` (`branch_id`);

--
-- Indexes for table `returns`
--
ALTER TABLE `returns`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_returns_transaction` (`transaction_id`),
  ADD KEY `idx_returns_product` (`product_id`);

--
-- Indexes for table `stock_movements`
--
ALTER TABLE `stock_movements`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_stock_branch` (`branch_id`),
  ADD KEY `idx_stock_product_branch` (`product_id`,`branch_id`);

--
-- Indexes for table `transactions`
--
ALTER TABLE `transactions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_transactions_user` (`user_id`),
  ADD KEY `idx_transactions_branch` (`branch_id`);

--
-- Indexes for table `transaction_items`
--
ALTER TABLE `transaction_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_ti_transaction` (`transaction_id`),
  ADD KEY `idx_ti_product` (`product_id`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_users_branch` (`branch_id`);

--
-- Indexes for table `vouchers`
--
ALTER TABLE `vouchers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`code`),
  ADD KEY `idx_target_id` (`target_id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `branches`
--
ALTER TABLE `branches`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT for table `categories`
--
ALTER TABLE `categories`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `payments`
--
ALTER TABLE `payments`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `products`
--
ALTER TABLE `products`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT for table `returns`
--
ALTER TABLE `returns`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `stock_movements`
--
ALTER TABLE `stock_movements`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `transactions`
--
ALTER TABLE `transactions`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `transaction_items`
--
ALTER TABLE `transaction_items`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `vouchers`
--
ALTER TABLE `vouchers`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `payments`
--
ALTER TABLE `payments`
  ADD CONSTRAINT `fk_payments_transaction` FOREIGN KEY (`transaction_id`) REFERENCES `transactions` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `products`
--
ALTER TABLE `products`
  ADD CONSTRAINT `fk_products_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_products_category` FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Constraints for table `returns`
--
ALTER TABLE `returns`
  ADD CONSTRAINT `fk_returns_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_returns_transaction` FOREIGN KEY (`transaction_id`) REFERENCES `transactions` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `stock_movements`
--
ALTER TABLE `stock_movements`
  ADD CONSTRAINT `fk_stock_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_stock_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `transactions`
--
ALTER TABLE `transactions`
  ADD CONSTRAINT `fk_transactions_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_transactions_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

--
-- Constraints for table `transaction_items`
--
ALTER TABLE `transaction_items`
  ADD CONSTRAINT `fk_ti_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_ti_transaction` FOREIGN KEY (`transaction_id`) REFERENCES `transactions` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `users`
--
ALTER TABLE `users`
  ADD CONSTRAINT `fk_users_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
