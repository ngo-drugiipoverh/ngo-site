const express = require("express");
const multer = require("multer");
const pool = require("../db");

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
      "home"
    ]
  );

  return result.rows[0].id;
}

router.get("/", async (req, res) => {
  try {
    const page = await pool.query(`
      SELECT
        h.*,
        f.file_path AS hero_image_url
      FROM home_page h
      LEFT JOIN files f
        ON f.id = h.hero_image_id
      WHERE h.id = 1
      LIMIT 1
    `);

    const stats = await pool.query(`
      SELECT *
      FROM home_stats
      ORDER BY sort_order ASC
    `);

    const vision = await pool.query(`
      SELECT *
      FROM home_vision_cards
      ORDER BY sort_order ASC
    `);

    const values = await pool.query(`
      SELECT *
      FROM home_values
      ORDER BY sort_order ASC
    `);

    const team = await pool.query(`
      SELECT
        tm.*,
        f.file_path AS photo_url
      FROM team_members tm
      LEFT JOIN files f
        ON f.id = tm.photo_id
      WHERE
        tm.is_deleted = FALSE
        AND tm.is_visible = TRUE
      ORDER BY tm.sort_order ASC, tm.created_at DESC
      LIMIT 8
    `);

    res.json({
      page: page.rows[0],
      stats: stats.rows,
      vision: vision.rows,
      values: values.rows,
      team: team.rows
    });

  } catch (error) {
    console.error("GET /api/home error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.put("/", upload.single("hero_image"), async (req, res) => {
  try {
    const body = req.body;

    let heroImageId = null;

    if (req.file) {
      heroImageId = await saveFile(req.file);
    }

    await pool.query(
      `
      UPDATE home_page
      SET
        hero_pill = $1,
        hero_title = $2,
        hero_description = $3,

        hero_primary_text = $4,
        hero_primary_url = $5,
        hero_secondary_text = $6,
        hero_secondary_url = $7,

        hero_badge_1 = $8,
        hero_badge_2 = $9,
        hero_badge_3 = $10,

        hero_card_title = $11,
        hero_card_text = $12,
        hero_image_id = COALESCE($13, hero_image_id),

        stats_title = $14,
        stats_description = $15,

        mission_title = $16,
        mission_text = $17,
        mission_item_1 = $18,
        mission_item_2 = $19,
        mission_item_3 = $20,

        mission_callout_title = $21,
        mission_callout_text = $22,
        mission_callout_link_text = $23,
        mission_callout_link_url = $24,

        vision_title = $25,
        vision_description = $26,

        values_title = $27,
        values_description = $28,

        team_title = $29,
        team_description = $30,

        join_title = $31,
        join_text = $32,
        join_primary_text = $33,
        join_primary_url = $34,
        join_secondary_text = $35,
        join_secondary_url = $36,

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

        body.hero_badge_1 || null,
        body.hero_badge_2 || null,
        body.hero_badge_3 || null,

        body.hero_card_title || null,
        body.hero_card_text || null,
        heroImageId,

        body.stats_title || null,
        body.stats_description || null,

        body.mission_title || null,
        body.mission_text || null,
        body.mission_item_1 || null,
        body.mission_item_2 || null,
        body.mission_item_3 || null,

        body.mission_callout_title || null,
        body.mission_callout_text || null,
        body.mission_callout_link_text || null,
        body.mission_callout_link_url || null,

        body.vision_title || null,
        body.vision_description || null,

        body.values_title || null,
        body.values_description || null,

        body.team_title || null,
        body.team_description || null,

        body.join_title || null,
        body.join_text || null,
        body.join_primary_text || null,
        body.join_primary_url || null,
        body.join_secondary_text || null,
        body.join_secondary_url || null
      ]
    );

    await pool.query("DELETE FROM home_stats");
    await pool.query("DELETE FROM home_vision_cards");
    await pool.query("DELETE FROM home_values");

    for (let i = 1; i <= 4; i++) {
      if (body[`stat_${i}_number`] || body[`stat_${i}_label`]) {
        await pool.query(
          `
          INSERT INTO home_stats (
            number_text,
            label,
            sort_order
          )
          VALUES ($1,$2,$3)
          `,
          [
            body[`stat_${i}_number`] || "",
            body[`stat_${i}_label`] || "",
            i
          ]
        );
      }
    }

    for (let i = 1; i <= 3; i++) {
      if (body[`vision_${i}_title`] || body[`vision_${i}_description`]) {
        await pool.query(
          `
          INSERT INTO home_vision_cards (
            title,
            description,
            sort_order
          )
          VALUES ($1,$2,$3)
          `,
          [
            body[`vision_${i}_title`] || "",
            body[`vision_${i}_description`] || "",
            i
          ]
        );
      }
    }

    for (let i = 1; i <= 4; i++) {
      if (body[`value_${i}_title`] || body[`value_${i}_description`]) {
        await pool.query(
          `
          INSERT INTO home_values (
            title,
            description,
            sort_order
          )
          VALUES ($1,$2,$3)
          `,
          [
            body[`value_${i}_title`] || "",
            body[`value_${i}_description`] || "",
            i
          ]
        );
      }
    }

    res.json({
      success: true
    });

  } catch (error) {
    console.error("PUT /api/home error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

module.exports = router;