-- MQTT connect script with deep sleep
-- Remember to connect GPIO16 and RST to enable deep sleep

--- MQTT ---
mqtt_broker_host = "io.adafruit.com"
mqtt_broker_port = 1883
mqtt_username = "<MQTT_USER>"
mqtt_password = "<MQTT_PASSWORD>"
mqtt_client_id = "esp8266_temp_humi"

--- WIFI ---
wifi_SSID = "<SSID>"
wifi_password = "<PASSWORD>"
-- wifi.PHYMODE_B 802.11b, More range, Low Transfer rate, More current draw
-- wifi.PHYMODE_G 802.11g, Medium range, Medium transfer rate, Medium current draw
-- wifi.PHYMODE_N 802.11n, Least range, Fast transfer rate, Least current draw
wifi_signal_mode = wifi.PHYMODE_N
-- If the settings below are filled out then the module connects
-- using a static ip address which is faster than DHCP and
-- better for battery life. Blank "" will use DHCP.
-- My own tests show around 1-2 seconds with static ip
-- and 4+ seconds for DHCP
client_ip = "192.168.1.172"
client_netmask = "255.255.255.0"
client_gateway = "192.168.1.1"

--- INTERVAL ---
-- In milliseconds. Remember that the sensor reading,
-- reboot and wifi reconnect takes a few seconds. Since the program takes
-- approximately 4.5s to execute, we delay 55.5s to make it run every minute
time_between_sensor_readings = 55500

-- Setup MQTT client and events
m = mqtt.Client(mqtt_client_id, 120, mqtt_username, mqtt_password)
temperature = 0
humidity = 0

-- Connect to the wifi network
wifi.setmode(wifi.STATION)
wifi.setphymode(wifi_signal_mode)
wifi.sta.config(wifi_SSID, wifi_password)
wifi.sta.connect()
if client_ip ~= "" then
  wifi.sta.setip({ip=client_ip,netmask=client_netmask,gateway=client_gateway})
end

-- HDC1000 sensor logic
function get_sensor_Data()
  HDC1000 = require("HDC1000")
  HDC1000.init(1,2,false)
  HDC1000.config()
  temperature = string.format("%.1f", HDC1000.getTemp() * 1.8 + 32)
  humidity = string.format("%.1f", HDC1000.getHumi())
  HDC1000 = nil
  package.loaded["HDC1000"] = nil
  voltage = string.format("%.3f", adc.readvdd33() / 1000)
end

function loop()
  if wifi.sta.status() == 5 then
    -- Stop the loop
    tmr.stop(0)
    m:connect(mqtt_broker_host, mqtt_broker_port, 0,
      function(conn)
        print("Connected to MQTT")
        print("  Host: "..mqtt_broker_host)
        print("  Port: "..mqtt_broker_port)
        print("  Client ID: "..mqtt_client_id)
        print("  Username: "..mqtt_username)
        -- Get sensor data
        get_sensor_Data()
        print("Temperature: "..temperature.."F")
        print("Humidity: "..humidity.."%")
        print("Voltage: "..voltage.."V")
        m:publish("davidlago/feeds/temperature", temperature, 0, 0, function(conn)
          m:publish("davidlago/feeds/humidity", humidity, 0, 0, function(conn)
            m:publish("davidlago/feeds/voltage", voltage, 0, 0, function(conn)
              print("Going to deep sleep for "..(time_between_sensor_readings / 1000).." seconds")
              node.dsleep(time_between_sensor_readings * 1000, 1)
            end)
          end)
        end)
      end,
      function(client, reason) print("failed reason: "..reason) end
    )
    else
      print("Connecting...")
    end
end

tmr.alarm(0, 100, 1, function() loop() end)

-- Make sure that if we're not done in 10 seconds we go back to sleep (maybe
-- network was down?)
tmr.alarm(1, 10000, 1, function()
  node.dsleep(time_between_sensor_readings * 1000, 1)
end)
