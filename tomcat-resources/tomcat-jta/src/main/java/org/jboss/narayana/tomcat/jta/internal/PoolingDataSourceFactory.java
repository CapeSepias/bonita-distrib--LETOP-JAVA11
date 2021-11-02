/*
 * Copyright 2018 Red Hat, Inc. and/or its affiliates.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.jboss.narayana.tomcat.jta.internal;

import static org.jboss.narayana.tomcat.jta.internal.XADataSourceIsSameRMOverride.overrideSameRM;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.sql.SQLException;
import java.util.Properties;
import java.util.logging.Level;
import java.util.logging.Logger;
import javax.sql.*;
import javax.transaction.TransactionManager;
import javax.transaction.TransactionSynchronizationRegistry;
import javax.transaction.xa.XAResource;

import org.apache.tomcat.dbcp.dbcp2.BasicDataSource;
import org.apache.tomcat.dbcp.dbcp2.BasicDataSourceFactory;
import org.apache.tomcat.dbcp.dbcp2.managed.BasicManagedDataSource;

import com.arjuna.ats.internal.jta.recovery.arjunacore.XARecoveryModule;
import com.arjuna.ats.jta.recovery.XAResourceRecoveryHelper;

public final class PoolingDataSourceFactory {

    private static final Logger LOGGER = Logger.getLogger(PoolingDataSourceFactory.class.getName());

    private static final String PROP_USERNAME = "username";
    private static final String PROP_PASSWORD = "password";

    static XAResourceRecoveryHelper getXAResourceRecoveryHelper(XADataSource xaDataSource, Properties properties) {
        return new XAResourceRecoveryHelper() {
            private final Object lock = new Object();
            private XAConnection connection;

            @Override
            public boolean initialise(String p) throws Exception {
                return true;
            }

            @Override
            public synchronized XAResource[] getXAResources() throws Exception {
                synchronized (lock) {
                    initialiseConnection();
                    try {
                        return new XAResource[]{connection.getXAResource()};
                    } catch (SQLException ex) {
                        return new XAResource[0];
                    }
                }
            }

            private void initialiseConnection() throws SQLException {
                // When going through recovery, a connection is most likely stale
                // We attempt to close it properly, and then re-create it

                if (connection != null) {
                    try {
                        LOGGER.fine("XAResourceRecoveryHelper : Detected a connection during XARecovery" + connection + " attempting to close it properly & generating a new one");
                        connection.close();

                    } catch (Exception e) {
                        LOGGER.log(Level.FINE, "XAResourceRecoveryHelper : The connection could not close properly, generating a new one", e);
                    } finally {
                        connection = null;
                    }
                }

                final String user = properties.getProperty(PROP_USERNAME);
                final String password = properties.getProperty(PROP_PASSWORD);

                if (user != null && password != null) {
                    connection = xaDataSource.getXAConnection(user, password);
                } else {
                    connection = xaDataSource.getXAConnection();
                }
                connection.addConnectionEventListener(new ConnectionEventListener() {
                    @Override
                    public void connectionClosed(ConnectionEvent event) {
                        LOGGER.warning("The connection was closed: " + connection);
                        synchronized (lock) {
                            connection = null;
                        }
                    }

                    @Override
                    public void connectionErrorOccurred(ConnectionEvent event) {
                        LOGGER.warning("A connection error occurred: " + connection);
                        synchronized (lock) {
                            try {
                                connection.close();
                            } catch (SQLException e) {
                                // Ignore
                                LOGGER.warning("Could not close failing connection: " + connection);
                            }
                            connection = null;
                        }
                    }
                });
            }
        };
    }

    public static DataSource createPoolingDataSource(final TransactionManager transactionManager,
                                                     final XADataSource xaDataSource,
                                                     final TransactionSynchronizationRegistry tsr,
                                                     final Properties properties) {
        if (transactionManager != null && xaDataSource != null) {
            /*
             * There is a trick to fix DBCP-215 so we have to remove the "initialSize" that
             * the BasicDataSourceFactory.createDataSource(properties) will not create the connections in the pool.
             * And it will create the connections with the BasicManagedDataSource later if the initialSize > 0.
             */
            String initialSize = properties.getProperty("initialSize");
            properties.remove("initialSize");
            BasicManagedDataSource mds = new BasicManagedDataSource();

            try {
                BasicDataSource ds = BasicDataSourceFactory.createDataSource(properties);

                for (Field field : ds.getClass().getDeclaredFields()) {
                    field.setAccessible(true);
                    if (field.get(ds) == null || Modifier.isFinal(field.getModifiers())) {
                        continue;
                    }
                    field.set(mds, field.get(ds));
                }

                mds.setTransactionManager(transactionManager);
                if (xaDataSource.getClass().getName().toLowerCase().contains("oracle")) {
                    LOGGER.finest("using overridden implementation for isSameRM flag (Oracle)");
                    mds.setXaDataSourceInstance(overrideSameRM(xaDataSource));
                } else {
                    LOGGER.finest("using default XA datasource implementation");
                    mds.setXaDataSourceInstance(xaDataSource);
                }
                mds.setTransactionSynchronizationRegistry(tsr);

                if (initialSize != null) {
                    mds.setInitialSize(Integer.parseInt(initialSize));
                    if (mds.getInitialSize() > 0) {
                        mds.getLogWriter();
                    }
                }
            } catch (Exception ex) {
                throw new RuntimeException(ex);
            }
            // Register for recovery
            XARecoveryModule xaRecoveryModule = getXARecoveryModule();
            if (xaRecoveryModule != null) {
                xaRecoveryModule.addXAResourceRecoveryHelper(getXAResourceRecoveryHelper(xaDataSource, properties));
            }

            return mds;
        } else {
            return null;
        }
    }

    private static XARecoveryModule getXARecoveryModule() {
        final XARecoveryModule xaRecoveryModule = XARecoveryModule.getRegisteredXARecoveryModule();
        if (xaRecoveryModule != null) {
            return xaRecoveryModule;
        }
        throw new IllegalStateException("XARecoveryModule is not registered with recovery manager");
    }
}
