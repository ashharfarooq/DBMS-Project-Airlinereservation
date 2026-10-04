import java.sql.Connection;
import java.sql.DriverManager;

public class DBConnection {
    private static final String DB_URL = "jdbc:sqlserver://DESKTOP-OMFKAIC\\SQLEXPRESS;databaseName=AirlineWEBDB;integratedSecurity=true;encrypt=false;trustServerCertificate=true;";

    public static Connection connect() {
        try {
            Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver");
            return DriverManager.getConnection(DB_URL);
        } catch (Exception e) {
            System.out.println("Connection failed!");
            e.printStackTrace();
            return null;
        }
    }
}
