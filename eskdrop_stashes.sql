-- Complete database table creation for eskdrop stashes system
-- This script creates the main stashes table with all required columns

CREATE TABLE IF NOT EXISTS `eskdrop_stashes` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `stash_id` varchar(255) NOT NULL,
  `owner_citizenid` varchar(50) NOT NULL,
  `owner_name` varchar(100) NOT NULL,
  `coords_x` float NOT NULL,
  `coords_y` float NOT NULL,
  `coords_z` float NOT NULL,
  `heading` float NOT NULL DEFAULT 0.0,
  `stash_type` varchar(50) NOT NULL DEFAULT 'spade',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at` timestamp NOT NULL,
  `last_accessed` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `stash_id` (`stash_id`),
  KEY `owner_citizenid` (`owner_citizenid`),
  KEY `expires_at` (`expires_at`),
  KEY `stash_type` (`stash_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Optional: Add indexes for better performance on large datasets
-- These are already included above but listed here for reference:
-- INDEX on stash_id (UNIQUE) - for fast stash lookups
-- INDEX on owner_citizenid - for finding player's stashes
-- INDEX on expires_at - for efficient cleanup of expired stashes
-- INDEX on stash_type - for filtering by stash type

-- Example data (optional - remove if not needed):
-- INSERT INTO `eskdrop_stashes` (`stash_id`, `owner_citizenid`, `owner_name`, `coords_x`, `coords_y`, `coords_z`, `heading`, `stash_type`, `expires_at`) 
-- VALUES ('example_stash_123', 'ABC12345', 'John Doe\'s Buried Stash', 123.45, 67.89, 10.11, 0.0, 'spade', DATE_ADD(NOW(), INTERVAL 1 HOUR));