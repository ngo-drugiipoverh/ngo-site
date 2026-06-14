const express = require("express");
const multer = require("multer");
const path = require("path");
const fs = require("fs");
const pool = require("../db");

const router = express.Router();

const uploadDir = path.join(
  __dirname,
  "../../uploads/library"
);

fs.mkdirSync(uploadDir, {
  recursive: true
});

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadDir);
  },

  filename: (req, file, cb) => {
    const safeName =
      file.originalname.replace(/\s+/g, "-");

    cb(
      null,
      Date.now() + "-" + safeName
    );
  }
});

const upload = multer({
  storage
});

router.get("/", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        li.*,
        f.file_path AS cover_image_url
      FROM library_items li
      LEFT JOIN files f
        ON f.id = li.cover_image_id
      WHERE li.is_deleted = FALSE
      ORDER BY li.created_at DESC
    `);

    res.json(result.rows);

  } catch (error) {
    console.error("GET library error:", error);

    res.status(500).json({
      error: "Server error"
    });
  }
});

router.post(
  "/",
  upload.single("cover"),
  async (req, res) => {
    const client = await pool.connect();

    try {
      await client.query("BEGIN");

      console.log("BODY:", req.body);

      const {
        title,
        item_type,
        author,
        genre,
        description
      } = req.body;

      let coverImageId = null;

      if (req.file) {
        const filePath =
          `/uploads/library/${req.file.filename}`;

        const fileResult =
          await client.query(`
            INSERT INTO files
            (
              original_name,
              stored_name,
              mime_type,
              file_path,
              file_size,
              entity_type,
              created_at
            )
            VALUES
            ($1,$2,$3,$4,$5,$6,NOW())
            RETURNING id
          `, [
            req.file.originalname,
            req.file.filename,
            req.file.mimetype,
            filePath,
            req.file.size,
            "library"
          ]);

        coverImageId =
          fileResult.rows[0].id;
      }

      const inserted =
        await client.query(`
          INSERT INTO library_items
          (
            title,
            item_type,
            author,
            genre,
            description,
            cover_image_id,
            created_at,
            updated_at,
            is_deleted
          )
          VALUES
          (
            $1,$2,$3,$4,$5,$6,
            NOW(),
            NOW(),
            FALSE
          )
          RETURNING *
        `, [
          title,
          item_type,
          author || null,
          genre || null,
          description || null,
          coverImageId
        ]);

      await client.query("COMMIT");

      console.log(
        "INSERTED:",
        inserted.rows[0]
      );

      res.status(201).json(
        inserted.rows[0]
      );

    } catch (error) {
      await client.query("ROLLBACK");

      console.error(
        "POST library error:",
        error
      );

      res.status(500).json({
        error: error.message
      });

    } finally {
      client.release();
    }
  }
);

router.delete("/:id", async (req, res) => {
  try {
    await pool.query(`
      UPDATE library_items
      SET is_deleted = TRUE
      WHERE id = $1
    `, [req.params.id]);

    res.json({
      ok: true
    });

  } catch (error) {
    console.error(
      "DELETE library error:",
      error
    );

    res.status(500).json({
      error: "Server error"
    });
  }
});

module.exports = router;