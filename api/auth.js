import fs from "fs";
import path from "path";

export default function handler(req, res) {
  const auth = req.headers.authorization;

  // إعداد اسم المستخدم وكلمة المرور
  const username = "admin";
  const password = "12345";

  // لو مفيش هيدر Authorization، اطلب تسجيل الدخول
  if (!auth) {
    res.setHeader("WWW-Authenticate", 'Basic realm="Restricted Area"');
    return res.status(401).send("Authentication required");
  }

  // فك تشفير الهيدر
  const [scheme, encoded] = auth.split(" ");
  if (scheme !== "Basic") {
    return res.status(400).send("Invalid authentication scheme");
  }

  const decoded = Buffer.from(encoded, "base64").toString();
  const [user, pass] = decoded.split(":");

  // تحقق من صحة بيانات الدخول
  if (user === username && pass === password) {
    try {
      // تحديد مسار ملف الـ bash
      const filePath = path.join(process.cwd(), "jishnu-manager.sh");
      const content = fs.readFileSync(filePath, "utf8");

      // إرجاع المحتوى كنص عادي
      res.setHeader("Content-Type", "text/plain; charset=utf-8");
      res.status(200).send(content);
    } catch (err) {
      res.status(500).send("Error reading script file: " + err.message);
    }
  } else {
    // لو كلمة السر أو اليوزر غلط
    res.setHeader("WWW-Authenticate", 'Basic realm="Restricted Area"');
    res.status(401).send("Unauthorized");
  }
}