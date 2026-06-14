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
      "direction"
    ]
  );

  return result.rows[0].id;
}

router.get("/", async (req, res) => {
  try {
    const page = await pool.query(`
      SELECT *
      FROM directions_page
      WHERE id = 1
      LIMIT 1
    `);

    const directions = await pool.query(`
      SELECT
        d.*,
        f.file_path AS cover_image_url
      FROM directions d
      LEFT JOIN files f
        ON f.id = d.cover_image_id
      WHERE
        d.is_deleted = FALSE
        AND d.is_published = TRUE
      ORDER BY
        d.sort_order ASC,
        d.created_at DESC
    `);

    res.json({
      page: page.rows[0],
      directions: directions.rows
    });

  } catch (error) {
    console.error("GET /api/directions error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.get("/admin", async (req, res) => {
  try {
    const page = await pool.query(`
      SELECT *
      FROM directions_page
      WHERE id = 1
      LIMIT 1
    `);

    const directions = await pool.query(`
      SELECT
        d.*,
        f.file_path AS cover_image_url
      FROM directions d
      LEFT JOIN files f
        ON f.id = d.cover_image_id
      WHERE d.is_deleted = FALSE
      ORDER BY
        d.sort_order ASC,
        d.created_at DESC
    `);

    res.json({
      page: page.rows[0],
      directions: directions.rows
    });

  } catch (error) {
    console.error("GET /api/directions/admin error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.put("/page", async (req, res) => {
  try {
    const body = req.body;

    await pool.query(
      `
      UPDATE directions_page
      SET
        hero_pill = $1,
        hero_title = $2,
        hero_description = $3,
        hero_primary_text = $4,
        hero_primary_url = $5,
        hero_secondary_text = $6,
        hero_secondary_url = $7,
        section_title = $8,
        section_description = $9,
        cta_title = $10,
        cta_text = $11,
        cta_button_text = $12,
        cta_button_url = $13,
        updated_at = NOW()
      WHERE id = 1
      `,
      [
        body.hero_pill || null,
        body.hero_title || null,
        body.hero_description || null,
        body.hero_primary_text || null,
        body.hero_primary_url || null,
        body.hero_secondary_text || null,
        body.hero_secondary_url || null,
        body.section_title || null,
        body.section_description || null,
        body.cta_title || null,
        body.cta_text || null,
        body.cta_button_text || null,
        body.cta_button_url || null
      ]
    );

    res.json({
      success: true
    });

  } catch (error) {
    console.error("PUT /api/directions/page error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.post("/", upload.single("cover"), async (req, res) => {
  try {
    const body = req.body;

    if (!body.title) {
      return res.status(400).json({
        error: "Назва напряму обов’язкова"
      });
    }

    let coverImageId = null;

    if (req.file) {
      coverImageId = await saveFile(req.file);
    }

    const result = await pool.query(
      `
      INSERT INTO directions (
        title,
        slug,
        short_description,
        full_description,
        icon,
        category,
        link_text,
        link_url,
        cover_image_id,
        sort_order,
        is_published,
        is_deleted,
        created_at,
        updated_at
      )
      VALUES
      ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,FALSE,NOW(),NOW())
      RETURNING *
      `,
      [
        body.title,
        body.slug || null,
        body.short_description || null,
        body.full_description || null,
        body.icon || null,
        body.category || null,
        body.link_text || null,
        body.link_url || null,
        coverImageId,
        Number(body.sort_order || 0),
        body.is_published === "false" ? false : true
      ]
    );

    res.status(201).json(result.rows[0]);

  } catch (error) {
    console.error("POST /api/directions error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.put("/:id", upload.single("cover"), async (req, res) => {
  try {
    const body = req.body;

    let coverImageId = null;

    if (req.file) {
      coverImageId = await saveFile(req.file);
    }

    const result = await pool.query(
      `
      UPDATE directions
      SET
        title = $1,
        slug = $2,
        short_description = $3,
        full_description = $4,
        icon = $5,
        category = $6,
        link_text = $7,
        link_url = $8,
        cover_image_id = COALESCE($9, cover_image_id),
        sort_order = $10,
        is_published = $11,
        updated_at = NOW()
      WHERE id = $12
      RETURNING *
      `,
      [
        body.title,
        body.slug || null,
        body.short_description || null,
        body.full_description || null,
        body.icon || null,
        body.category || null,
        body.link_text || null,
        body.link_url || null,
        coverImageId,
        Number(body.sort_order || 0),
        body.is_published === "false" ? false : true,
        req.params.id
      ]
    );

    res.json(result.rows[0]);

  } catch (error) {
    console.error("PUT /api/directions/:id error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.delete("/:id", async (req, res) => {
  try {
    await pool.query(
      `
      UPDATE directions
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
    console.error("DELETE /api/directions/:id error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

module.exports = router;