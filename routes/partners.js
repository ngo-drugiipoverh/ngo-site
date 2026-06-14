const express = require("express");
const pool = require("../db");
const multer = require("multer");

const router = express.Router();

const upload = multer({
  dest: "uploads/"
});

async function saveFile(file) {
  const result = await pool.query(
    `
    INSERT INTO files (
      original_name,
      stored_name,
      mime_type,
      file_path
    )
    VALUES ($1,$2,$3,$4)
    RETURNING id
    `,
    [
      file.originalname,
      file.filename,
      file.mimetype,
      `/uploads/${file.filename}`
    ]
  );

  return result.rows[0].id;
}

router.get("/", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        p.*,
        f.file_path AS logo_url
      FROM partners p
      LEFT JOIN files f
        ON f.id = p.logo_id
      WHERE p.is_deleted = FALSE
      ORDER BY p.sort_order ASC, p.created_at DESC
    `);

    res.json(result.rows);
  } catch (error) {
    res.status(500).json({
      error: error.message
    });
  }
});

router.post("/", upload.single("logo"), async (req, res) => {
  try {
    const {
      name,
      website_url,
      description
    } = req.body;

    let logoId = null;

    if (req.file) {
      logoId = await saveFile(req.file);
    }

    const result = await pool.query(
      `
      INSERT INTO partners (
        name,
        website_url,
        description,
        logo_id,
        is_deleted,
        created_at,
        updated_at
      )
      VALUES ($1,$2,$3,$4,FALSE,NOW(),NOW())
      RETURNING *
      `,
      [
        name,
        website_url || null,
        description || null,
        logoId
      ]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    res.status(500).json({
      error: error.message
    });
  }
});

router.put("/:id", upload.single("logo"), async (req, res) => {
  try {
    const {
      name,
      website_url,
      description
    } = req.body;

    let logoId = null;

    if (req.file) {
      logoId = await saveFile(req.file);
    }

    const result = await pool.query(
      `
      UPDATE partners
      SET
        name = $1,
        website_url = $2,
        description = $3,
        logo_id = COALESCE($4, logo_id),
        updated_at = NOW()
      WHERE id = $5
      RETURNING *
      `,
      [
        name,
        website_url || null,
        description || null,
        logoId,
        req.params.id
      ]
    );

    res.json(result.rows[0]);
  } catch (error) {
    res.status(500).json({
      error: error.message
    });
  }
});

router.delete("/:id", async (req, res) => {
  try {
    await pool.query(
      `
      UPDATE partners
      SET
        is_deleted = TRUE,
        deleted_at = NOW(),
        updated_at = NOW()
      WHERE id = $1
      `,
      [req.params.id]
    );

    res.json({
      success: true
    });
  } catch (error) {
    res.status(500).json({
      error: error.message
    });
  }
});

module.exports = router;