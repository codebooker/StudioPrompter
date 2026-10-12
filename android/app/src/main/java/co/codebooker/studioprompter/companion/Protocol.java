package co.codebooker.studioprompter.companion;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;

public final class Protocol {
    public static final int MAX_BYTES = 8 * 1024 * 1024;
    public static String normalize(String value) { return value.toUpperCase(Locale.ROOT).replaceAll("[^A-Z0-9]", ""); }
    public static byte[] hash(String value) {
        try { return MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)); }
        catch (Exception e) { throw new IllegalStateException(e); }
    }
    public static String identity(String value) {
        StringBuilder hex = new StringBuilder();
        for (byte b : hash("identity:" + normalize(value))) hex.append(String.format(Locale.ROOT, "%02x", b & 255));
        return "StudioPrompter-v2-" + hex;
    }
    public static JSONObject read(DataInputStream input) throws Exception {
        int size = input.readInt();
        if (size <= 0 || size > MAX_BYTES) throw new IOException("Invalid message size");
        byte[] bytes = new byte[size]; input.readFully(bytes);
        return new JSONObject(new String(bytes, StandardCharsets.UTF_8));
    }
    public static void write(DataOutputStream output, JSONObject message) throws Exception {
        byte[] bytes = message.toString().getBytes(StandardCharsets.UTF_8);
        if(bytes.length == 0 || bytes.length > MAX_BYTES) throw new IOException("Invalid message size");
        output.writeInt(bytes.length); output.write(bytes); output.flush();
    }
    public static JSONObject message(String name, JSONObject value) throws JSONException { return new JSONObject().put(name, value); }
    private static boolean bounded(double n, double min, double max) { return Double.isFinite(n) && n >= min && n <= max; }
    public static boolean validDocument(JSONObject doc) {
        try {
            String text=doc.getJSONObject("script").getString("text"); JSONObject s=doc.getJSONObject("script").getJSONObject("settings");
            java.util.UUID.fromString(doc.getString("revision"));
            if(text.length()>500000 || !bounded(doc.getDouble("textHeight"),0,10000000) || !bounded(doc.getDouble("lineHeight"),1,1000) ||
                !bounded(s.getDouble("fontSize"),1,200) || !bounded(s.getDouble("margin"),0,450) ||
                !bounded(s.getDouble("guidePosition"),0,1) || !bounded(s.getDouble("guideLines"),1,3)) return false;
            JSONArray lines=doc.getJSONArray("lines");if(lines.length()>100000)return false;
            for(int i=0;i<lines.length();i++){JSONObject l=lines.getJSONObject(i);double loc=l.getDouble("location"),len=l.getDouble("length");
                if(loc!=Math.floor(loc)||len!=Math.floor(len)||loc<0||len<0||loc+len>text.length() || !bounded(l.getDouble("y"),0,10000000)||!bounded(l.getDouble("height"),0,1000))return false;}
            return true;
        } catch(Exception e){return false;}
    }
    public static boolean validPlayback(JSONObject p,String revision) {
        try {return p.getString("revision").equals(revision)&&bounded(p.getDouble("progress"),0,1)&&bounded(p.getDouble("countdown"),0,10)&&p.getDouble("countdown")==p.getInt("countdown")&&p.get("playing") instanceof Boolean&&p.get("blackout") instanceof Boolean&&p.optString("notice","").length()<=4096;}
        catch(Exception e){return false;}
    }
}
