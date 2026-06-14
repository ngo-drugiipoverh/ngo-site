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
      file_path,
      file_size,
      entity_type,
      created_at
    )
    VALUES ($1,$2,$3,$4,$5,$6,NOW())
    RETURNING id
    `,
    [
      file.originalname,
      file.filename,
      file.mimetype,
      `/uploads/${file.filename}`,
      file.size || 0,
      "project"
    ]
  );

  return result.rows[0].id;
}

router.get("/", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        p.*,
        f.file_path AS cover_image_url
      FROM projects p
      LEFT JOIN files f
        ON f.id = p.cover_image_id
      WHERE p.is_deleted = FALSE
      ORDER BY p.sort_order ASC, p.created_at DESC
    `);

    res.json(result.rows);

  } catch (error) {
    console.error("GET /api/projects error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.post("/", upload.single("cover"), async (req, res) => {
  try {
    const {
      title,
      slug,
      short_description,
      full_description,
      status,
      start_date,
      end_date,
      sort_order
    } = req.body;

    if (!title || !slug) {
      return res.status(400).json({
        error: "Назва і slug обов’язкові"
      });
    }

    let coverImageId = null;

    if (req.file) {
      coverImageId = await saveFile(req.file);
    }

    const result = await pool.query(
      `
      INSERT INTO projects (
        title,
        slug,
        short_description,
        full_description,
        status,
        start_date,
        end_date,
        sort_order,
        cover_image_id,
        is_deleted,
        created_at,
        updated_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,FALSE,NOW(),NOW())
      RETURNING *
      `,
      [
        title,
        slug,
        short_description || null,
        full_description || null,
        status || "active",
        start_date || null,
        end_date || null,
        Number(sort_order || 0),
        coverImageId
      ]
    );

    res.status(201).json(result.rows[0]);

  } catch (error) {
    console.error("POST /api/projects error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.put("/:id", upload.single("cover"), async (req, res) => {
  try {
    const {
      title,
      slug,
      short_description,
      full_description,
      status,
      start_date,
      end_date,
      sort_order
    } = req.body;

    let coverImageId = null;

    if (req.file) {
      coverImageId = await saveFile(req.file);
    }

    const result = await pool.query(
      `
      UPDATE projects
      SET
        title = $1,
        slug = $2,
        short_description = $3,
        full_description = $4,
        status = $5,
        start_date = $6,
        end_date = $7,
        sort_order = $8,
        cover_image_id = COALESCE($9, cover_image_id),
        updated_at = NOW()
      WHERE id = $10
      RETURNING *
      `,
      [
        title,
        slug,
        short_description || null,
        full_description || null,
        status || "active",
        start_date || null,
        end_date || null,
        Number(sort_order || 0),
        coverImageId,
        req.params.id
      ]
    );

    res.json(result.rows[0]);

  } catch (error) {
    console.error("PUT /api/projects/:id error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.delete("/:id", async (req, res) => {
  try {
    await pool.query(
      `
      UPDATE projects
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
    console.error("DELETE /api/projects/:id error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

module.exports = router;