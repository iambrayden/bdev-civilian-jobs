-- bdev-civilian-jobs creates this table by itself on first start.
-- Run this by hand only if your database user can't create tables.
CREATE TABLE IF NOT EXISTS `civjobs_stats` (
    `citizenid` VARCHAR(50) NOT NULL,
    `job` VARCHAR(50) NOT NULL,
    `xp` INT NOT NULL DEFAULT 0,
    `completed` INT NOT NULL DEFAULT 0,
    `earned` BIGINT NOT NULL DEFAULT 0,
    `rating_total` INT NOT NULL DEFAULT 0,
    `rating_count` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`citizenid`, `job`)
);
