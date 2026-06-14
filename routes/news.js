const express = require("express");
const multer = require("multer");
const path = require("path");
const fs = require("fs");
const pool = require("../db");

const router = express.Router();

const uploadDir = path.join(__dirname, "../../uploads/news");

fs.mkdirSync(uploadDir, {
  recursive: true
});

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadDir);
  },

  filename: (req, file, cb) => {
    cb(
      null,
      Date.now() +
      "-" +
      file.originalname.replace(/\s+/g, "-")
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
        p.*,
        f.file_path AS cover_image_url
      FROM publications p
      LEFT JOIN files f
        ON f.id = p.cover_image_id
      WHERE p.is_deleted = FALSE
      ORDER BY p.created_at DESC
    `);

    res.json(result.rows);

  } catch (error) {
    console.error(error);

    res.status(500).json({
      error: error.message
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

      const {
        title,
        slug,
        excerpt,
        content,
        status
      } = req.body;

      let coverImageId = null;

      if (req.file) {

        const filePath =
          `/uploads/news/${req.file.filename}`;

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
            "publication"
          ]);

        coverImageId =
          fileResult.rows[0].id;
      }

      const categoryResult =
        await client.query(`
          SELECT id
          FROM publication_categories
          LIMIT 1
        `);

      const categoryId =
        categoryResult.rows[0]?.id;

      const result =
        await client.query(`
          INSERT INTO publications
          (
            title,
            slug,
            excerpt,
            content,
            status,
            category_id,
            cover_image_id,
            published_at,
            created_at,
            updated_at,
            is_deleted
          )
          VALUES
          (
            $1,$2,$3,$4,$5,$6,$7,
            NOW(),
            NOW(),
            NOW(),
            FALSE
          )
          RETURNING *
        `, [
          title,
          slug,
          excerpt || null,
          content || null,
          status || "draft",
          categoryId,
          coverImageId
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

  }
);

router.put(
  "/:id",
  upload.single("cover"),
  async (req, res) => {

    const client = await pool.connect();

    try {

      await client.query("BEGIN");

      const {
        title,
        slug,
        excerpt,
        content,
        status
      } = req.body;

      let coverImageId = null;

      if (req.file) {

        const filePath =
          `/uploads/news/${req.file.filename}`;

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
            "publication"
          ]);

        coverImageId =
          fileResult.rows[0].id;
      }

      if (coverImageId) {

        await client.query(`
          UPDATE publications
          SET
            title = $1,
            slug = $2,
            excerpt = $3,
            content = $4,
            status = $5,
            cover_image_id = $6,
            updated_at = NOW()
          WHERE id = $7
        `, [
          title,
          slug,
          excerpt || null,
          content || null,
          status || "draft",
          coverImageId,
          req.params.id
        ]);

      } else {

        await client.query(`
          UPDATE publications
          SET
            title = $1,
            slug = $2,
            excerpt = $3,
            content = $4,
            status = $5,
            updated_at = NOW()
          WHERE id = $6
        `, [
          title,
          slug,
          excerpt || null,
          content || null,
          status || "draft",
          req.params.id
        ]);

      }

      await client.query("COMMIT");

      res.json({
        ok: true
      });

    } catch (error) {

      await client.query("ROLLBACK");

      console.error(error);

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
      UPDATE publications
      SET
        is_deleted = TRUE,
        updated_at = NOW()
      WHERE id = $1
    `, [req.params.id]);

    res.json({
      ok: true
    });

  } catch (error) {

    console.error(error);

    res.status(500).json({
      error: error.message
    });

  }
});

module.exports = router;