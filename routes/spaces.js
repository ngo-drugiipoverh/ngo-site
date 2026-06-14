const express = require("express");
const pool = require("../db");
const multer = require("multer");

const router = express.Router();

const upload = multer({
  dest: "uploads/"
});

router.get("/second-floor", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        s.*,
        cover.file_path AS cover_image_url,
        booking.file_path AS booking_image_url
      FROM spaces s
      LEFT JOIN files cover
        ON cover.id = s.cover_image_id
      LEFT JOIN files booking
        ON booking.id = s.booking_image_id
      WHERE s.slug = 'second-floor'
      LIMIT 1
    `);

    if (!result.rows.length) {
      return res.status(404).json({
        error: "Space not found"
      });
    }

    res.json(result.rows[0]);

  } catch (error) {
    console.error(error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.put(
  "/second-floor",
  upload.fields([
    { name: "cover_image", maxCount: 1 },
    { name: "booking_image", maxCount: 1 }
  ]),
  async (req, res) => {
    try {

      const {
        title,
        description,
        coworking_text,
        studio_text
      } = req.body;

      let coverImageId = null;
      let bookingImageId = null;

      if (req.files?.cover_image?.[0]) {

        const file = req.files.cover_image[0];

        const saved = await pool.query(
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

        coverImageId = saved.rows[0].id;
      }

      if (req.files?.booking_image?.[0]) {

        const file = req.files.booking_image[0];

        const saved = await pool.query(
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

        bookingImageId = saved.rows[0].id;
      }

      await pool.query(
        `
        UPDATE spaces
        SET
          name = $1,
          description = $2,
          short_description = $3,
          studio_description = $4,
          cover_image_id = COALESCE($5, cover_image_id),
          booking_image_id = COALESCE($6, booking_image_id),
          updated_at = NOW()
        WHERE slug = 'second-floor'
        `,
        [
          title,
          description,
          coworking_text || null,
          studio_text || null,
          coverImageId,
          bookingImageId
        ]
      );

      const updated = await pool.query(`
        SELECT
          s.*,
          cover.file_path AS cover_image_url,
          booking.file_path AS booking_image_url
        FROM spaces s
        LEFT JOIN files cover
          ON cover.id = s.cover_image_id
        LEFT JOIN files booking
          ON booking.id = s.booking_image_id
        WHERE s.slug = 'second-floor'
        LIMIT 1
      `);

      res.json(updated.rows[0]);

    } catch (error) {

      console.error(error);

      res.status(500).json({
        error: error.message
      });

    }
  }
);

module.exports = router;