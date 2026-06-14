const express = require("express");
const pool = require("../db");

const router = express.Router();

router.get("/", async (req, res) => {
  try {
    const page = await pool.query(`
      SELECT *
      FROM about_page
      WHERE id = 1
      LIMIT 1
    `);

    const stats = await pool.query(`
      SELECT *
      FROM about_stats
      ORDER BY sort_order ASC
    `);

    const mvv = await pool.query(`
      SELECT *
      FROM about_mvv_cards
      ORDER BY sort_order ASC
    `);

    const directions = await pool.query(`
      SELECT *
      FROM about_directions
      ORDER BY sort_order ASC
    `);

    res.json({
      page: page.rows[0],
      stats: stats.rows,
      mvv: mvv.rows,
      directions: directions.rows
    });

  } catch (error) {
    console.error("GET /api/about error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.put("/", async (req, res) => {
  try {
    const body = req.body;

    await pool.query(
      `
      UPDATE about_page
      SET
        hero_pill = $1,
        hero_title = $2,
        hero_description = $3,
        hero_primary_text = $4,
        hero_primary_url = $5,
        hero_secondary_text = $6,
        hero_secondary_url = $7,

        hero_card_badge = $8,
        hero_card_title = $9,
        hero_card_text = $10,
        hero_card_item_1 = $11,
        hero_card_item_2 = $12,
        hero_card_item_3 = $13,

        about_title = $14,
        about_description = $15,
        about_text = $16,

        mvv_title = $17,
        mvv_description = $18,

        directions_title = $19,
        directions_description = $20,

        cta_title = $21,
        cta_text = $22,
        cta_button_1_text = $23,
        cta_button_1_url = $24,
        cta_button_2_text = $25,
        cta_button_2_url = $26,
        cta_button_3_text = $27,
        cta_button_3_url = $28,

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

        body.hero_card_badge || null,
        body.hero_card_title || null,
        body.hero_card_text || null,
        body.hero_card_item_1 || null,
        body.hero_card_item_2 || null,
        body.hero_card_item_3 || null,

        body.about_title || null,
        body.about_description || null,
        body.about_text || null,

        body.mvv_title || null,
        body.mvv_description || null,

        body.directions_title || null,
        body.directions_description || null,

        body.cta_title || null,
        body.cta_text || null,
        body.cta_button_1_text || null,
        body.cta_button_1_url || null,
        body.cta_button_2_text || null,
        body.cta_button_2_url || null,
        body.cta_button_3_text || null,
        body.cta_button_3_url || null
      ]
    );

    await pool.query("DELETE FROM about_stats");
    await pool.query("DELETE FROM about_mvv_cards");
    await pool.query("DELETE FROM about_directions");

    for (let i = 1; i <= 3; i++) {
      if (body[`stat_${i}_number`] || body[`stat_${i}_label`]) {
        await pool.query(
          `
          INSERT INTO about_stats (number_text, label, sort_order)
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
      if (body[`mvv_${i}_title`] || body[`mvv_${i}_description`]) {
        await pool.query(
          `
          INSERT INTO about_mvv_cards (icon, title, description, sort_order)
          VALUES ($1,$2,$3,$4)
          `,
          [
            body[`mvv_${i}_icon`] || "",
            body[`mvv_${i}_title`] || "",
            body[`mvv_${i}_description`] || "",
            i
          ]
        );
      }
    }

    for (let i = 1; i <= 4; i++) {
      if (body[`direction_${i}_title`] || body[`direction_${i}_description`]) {
        await pool.query(
          `
          INSERT INTO about_directions (
            title,
            description,
            link_text,
            link_url,
            sort_order
          )
          VALUES ($1,$2,$3,$4,$5)
          `,
          [
            body[`direction_${i}_title`] || "",
            body[`direction_${i}_description`] || "",
            body[`direction_${i}_link_text`] || "",
            body[`direction_${i}_link_url`] || "",
            i
          ]
        );
      }
    }

    res.json({
      success: true
    });

  } catch (error) {
    console.error("PUT /api/about error:", error);

    res.status(500).json({
      error: error.message
    });
  }
});

module.exports = router;