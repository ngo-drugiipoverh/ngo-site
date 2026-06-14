const express = require("express");
const multer = require("multer");
const path = require("path");
const fs = require("fs");
const pool = require("../db");

const router = express.Router();

const uploadDir = path.join(__dirname, "../../uploads/team");
fs.mkdirSync(uploadDir, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const safeName = file.originalname.replace(/\s+/g, "-");
    cb(null, Date.now() + "-" + safeName);
  }
});

const upload = multer({ storage });

router.get("/", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        tm.id,
        tm.first_name,
        tm.last_name,
        tm.role_title,
        tm.bio,
        tm.instagram_url,
        tm.telegram_url,
        tm.sort_order,
        tm.photo_position_x,
        tm.photo_position_y,
        f.file_path AS photo_url,
        f.alt_text AS photo_alt
      FROM team_members tm
      LEFT JOIN files f ON f.id = tm.photo_id
      WHERE tm.is_visible = TRUE
        AND tm.is_deleted = FALSE
      ORDER BY tm.sort_order ASC, tm.created_at ASC
    `);

    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({
      error: "Server error"
    });
  }
});

router.post("/", upload.single("photo"), async (req, res) => {
  const client = await pool.connect();

  try {
const {
  first_name,
  last_name,
  role_title,
  bio,
  instagram_url,
  telegram_url,
  sort_order,
  photo_position_x,
  photo_position_y
} = req.body;

    await client.query("BEGIN");

    let photoId = null;

    if (req.file) {
      const filePath = `/uploads/team/${req.file.filename}`;

      const fileResult = await client.query(`
        INSERT INTO files
        (
          original_name,
          stored_name,
          mime_type,
          file_path,
          file_size,
          alt_text,
          entity_type,
          created_at
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,NOW())
        RETURNING id
      `, [
        req.file.originalname,
        req.file.filename,
        req.file.mimetype,
        filePath,
        req.file.size,
        `${first_name} ${last_name}`,
        "team_member"
      ]);

      photoId = fileResult.rows[0].id;
    }

const result = await client.query(`
  INSERT INTO team_members
  (
    first_name,
    last_name,
    role_title,
    bio,
    instagram_url,
    telegram_url,
    sort_order,
    photo_id,
    photo_position_x,
    photo_position_y,
    is_visible,
    is_deleted,
    created_at
  )
  VALUES
  (
    $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,
    TRUE,
    FALSE,
    NOW()
  )
  RETURNING *
`, [
  first_name,
  last_name,
  role_title,
  bio || null,
  instagram_url || null,
  telegram_url || null,
  Number(sort_order) || 0,
  photoId,
  Number(photo_position_x) || 50,
  Number(photo_position_y) || 50
]);

    await client.query("COMMIT");

    res.status(201).json(result.rows[0]);

  } catch (error) {

    await client.query("ROLLBACK");

    console.error(error);

    res.status(500).json({
      error: error.message
    });

  } finally {
    client.release();
  }
});

router.put("/:id", upload.single("photo"), async (req, res) => {
  try {
    const { id } = req.params;

const {
  first_name,
  last_name,
  role_title,
  bio,
  instagram_url,
  telegram_url,
  sort_order,
  photo_position_x,
  photo_position_y
} = req.body;

await pool.query(`
  UPDATE team_members
  SET
    first_name = $1,
    last_name = $2,
    role_title = $3,
    bio = $4,
    instagram_url = $5,
    telegram_url = $6,
    sort_order = $7,
    photo_position_x = $8,
    photo_position_y = $9,
    updated_at = NOW()
  WHERE id = $10
`, [
  first_name,
  last_name,
  role_title,
  bio || null,
  instagram_url || null,
  telegram_url || null,
  Number(sort_order) || 0,
  Number(photo_position_x) || 50,
  Number(photo_position_y) || 50,
  id
]);

    res.json({
      message: "updated"
    });

  } catch (error) {

    console.error(error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.delete("/:id", async (req, res) => {
  try {

    await pool.query(`
      DELETE FROM team_members
      WHERE id = $1
    `, [req.params.id]);

    res.json({
      message: "deleted"
    });

  } catch (error) {

    console.error(error);

    res.status(500).json({
      error: error.message
    });
  }
});

module.exports = router;