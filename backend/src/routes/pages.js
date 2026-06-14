const express = require("express");
const router = express.Router();
const pool = require("../db");

router.get("/", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT id, slug, title, meta_description, meta_keywords, sort_order, parent_page_id
      FROM site_pages
      WHERE is_published = TRUE
      ORDER BY sort_order ASC, created_at ASC
    `);

    res.json(result.rows);
  } catch (error) {
    console.error("GET /api/pages error:", error);
    res.status(500).json({ error: "Server error" });
  }
});

router.get("/counters", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT id, label, icon, value, suffix, is_auto, auto_source, sort_order
      FROM site_counters
      WHERE is_visible = TRUE
      ORDER BY sort_order ASC, created_at ASC
    `);

    res.json(result.rows);
  } catch (error) {
    console.error("GET /api/pages/counters error:", error);
    res.status(500).json({ error: "Server error" });
  }
});

router.get("/:slug", async (req, res) => {
  const { slug } = req.params;

  try {
    const pageResult = await pool.query(`
      SELECT id, slug, title, meta_description, meta_keywords
      FROM site_pages
      WHERE slug = $1 AND is_published = TRUE
      LIMIT 1
    `, [slug]);

    if (pageResult.rows.length === 0) {
      return res.status(404).json({ error: "Page not found" });
    }

    const page = pageResult.rows[0];

    const blocksResult = await pool.query(`
      SELECT id, block_key, block_type, content, metadata, sort_order
      FROM site_content_blocks
      WHERE page_id = $1
      ORDER BY sort_order ASC, created_at ASC
    `, [page.id]);

    res.json({
      ...page,
      blocks: blocksResult.rows
    });
  } catch (error) {
    console.error("GET /api/pages/:slug error:", error);
    res.status(500).json({ error: "Server error" });
  }
});

module.exports = router;