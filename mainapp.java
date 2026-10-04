import java.sql.Connection;
import java.sql.Statement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;

public class MainApp {
    public static void main(String[] args) {
        Connection conn = DBConnection.connect();
        if (conn == null) {
            System.out.println("Connection failed!");
            return;
        }
        try {
            Statement stmt = conn.createStatement();
            ResultSet rs = stmt.executeQuery("SELECT TOP 5 * FROM Flight_Schedules");
            
            ResultSetMetaData metaData = rs.getMetaData();
            int columnCount = metaData.getColumnCount();

            System.out.println("\n--- FLIGHT SCHEDULES RECORDS ---");
            while (rs.next()) {
                StringBuilder rowData = new StringBuilder();
                for (int i = 1; i <= columnCount; i++) {
                    rowData.append(metaData.getColumnName(i)).append(": ").append(rs.getObject(i)).append(" | ");
                }
                System.out.println(rowData.toString());
            }
            conn.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
