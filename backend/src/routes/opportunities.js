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
      "opportunity"
    ]
  );

  return result.rows[0].id;
}

router.get("/", async (req, res) => {
  try {
    const page = await pool.query(`
      SELECT *
      FROM opportunities_page
      WHERE id = 1
      LIMIT 1
    `);

    const items = await pool.query(`
      SELECT
        o.*,
        f.file_path AS cover_image_url
      FROM opportunities o
      LEFT JOIN files f
        ON f.id = o.cover_image_id
      WHERE
        o.is_deleted = FALSE
        AND o.is_published = TRUE
      ORDER BY
        o.sort_order ASC,
        o.deadline_date ASC NULLS LAST,
        o.created_at DESC
    `);

    res.json({
      page: page.rows[0],
      opportunities: items.rows
    });

  } catch (error) {
    console.error("GET /api/opportunities error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.get("/admin", async (req, res) => {
  try {
    const page = await pool.query(`
      SELECT *
      FROM opportunities_page
      WHERE id = 1
      LIMIT 1
    `);

    const items = await pool.query(`
      SELECT
        o.*,
        f.file_path AS cover_image_url
      FROM opportunities o
      LEFT JOIN files f
        ON f.id = o.cover_image_id
      WHERE o.is_deleted = FALSE
      ORDER BY
        o.sort_order ASC,
        o.created_at DESC
    `);

    res.json({
      page: page.rows[0],
      opportunities: items.rows
    });

  } catch (error) {
    console.error("GET /api/opportunities/admin error:", error);

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
      UPDATE opportunities_page
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
    console.error("PUT /api/opportunities/page error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.post("/", upload.single("cover"), async (req, res) => {
  try {
    const body = req.body;

    let coverImageId = null;

    if (req.file) {
      coverImageId = await saveFile(req.file);
    }

    const result = await pool.query(
      `
      INSERT INTO opportunities (
        title,
        slug,
        short_description,
        full_description,
        category,
        format,
        deadline_date,
        location,
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
      ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,FALSE,NOW(),NOW())
      RETURNING *
      `,
      [
        body.title,
        body.slug || null,
        body.short_description || null,
        body.full_description || null,
        body.category || null,
        body.format || null,
        body.deadline_date || null,
        body.location || null,
        body.link_text || null,
        body.link_url || null,
        coverImageId,
        Number(body.sort_order || 0),
        body.is_published === "false" ? false : true
      ]
    );

    res.status(201).json(result.rows[0]);

  } catch (error) {
    console.error("POST /api/opportunities error:", error);

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
      UPDATE opportunities
      SET
        title = $1,
        slug = $2,
        short_description = $3,
        full_description = $4,
        category = $5,
        format = $6,
        deadline_date = $7,
        location = $8,
        link_text = $9,
        link_url = $10,
        cover_image_id = COALESCE($11, cover_image_id),
        sort_order = $12,
        is_published = $13,
        updated_at = NOW()
      WHERE id = $14
      RETURNING *
      `,
      [
        body.title,
        body.slug || null,
        body.short_description || null,
        body.full_description || null,
        body.category || null,
        body.format || null,
        body.deadline_date || null,
        body.location || null,
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
    console.error("PUT /api/opportunities/:id error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.delete("/:id", async (req, res) => {
  try {
    await pool.query(
      `
      UPDATE opportunities
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
    console.error("DELETE /api/opportunities/:id error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

module.exports = router;