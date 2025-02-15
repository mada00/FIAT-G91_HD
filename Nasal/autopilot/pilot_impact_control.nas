# Pilot Impact control system for advert and resolv collision situations
#
# 2019-10-25 Adriano Bassignana
# GPL 2.0+

var timeStep = 1.0;
var timeStepDivisor = 1.0;
var delta_time = 1.0;
var timeStepSecond = 0;

var testing_log_active = 0;

var pitch_angle_deg = 0.0;
var speed_fps = 0.0; 
var speed_horz_fps = 0.0;
var speed_down_fps = 0.0;
var imp_min_z_ft = 0.0;
var imp_min_z_ft_lag = 0.0;

var imp_medium_time = 0.0;
var imp_medium_time = 0.0;
var imp_cnt_active = 0;
var imp_al = 0.0;

var intensity_calc = 0.0;
var intensity_calc_lag = 0.0;
var intensity_calc_lag_versus = 0;
var neutre_lag = 0.0;
var neutre_lag_adv = 0.0;
var neutre_lag_n = 0;
var neutre_lag_active = 0;
var factor_neutre = 0.0;

var intensity_calc_lag_adv = std.Vector.new([]);
var intensity_calc_lag_acc = 0.0;
var intensity_T0_lag = 0.0;
var intensity_T1_lag = 0.0;
var intensity_T2_lag = 0.0;
var intensity_T3_lag = 0.0;
var intensity_T4_lag = 0.0;

var complex_factor = 1.0;
var complex_factor_target = 0.0;
var complex_factor_adv = std.Vector.new([]);
var complex_factor_acc = 0.0;



var radar_elv_beam = func(aAircraftPosition, aHeading, aSpeed_horz_fps, time_sec) {
    var xyz = {"x":aAircraftPosition.x(),"y":aAircraftPosition.y(),"z":aAircraftPosition.z()};
    var end = geo.Coord.new(aAircraftPosition);
    end.apply_course_distance(aHeading, aSpeed_horz_fps * time_sec * FT2M);
    return end;
}

var calculate_imp_geod = func(aAircraftPosition, aHeading, aPitch_angle_absolute) {
    var xyz = {"x":aAircraftPosition.x(),"y":aAircraftPosition.y(),"z":aAircraftPosition.z()};
    var end = geo.Coord.new(aAircraftPosition);
    end.apply_course_distance(aHeading, 1.0);
    var dir_x = end.x()-aAircraftPosition.x();
    var dir_y = end.y()-aAircraftPosition.y();
    var dir_z = math.tan(aPitch_angle_absolute * D2R);
    var dir = {"x":dir_x,"y":dir_y,"z":dir_z};
    return geod = get_cart_ground_intersection(xyz, dir);
}

var calculate_imp_elev = func(aGeod) {
    if (aGeod != nil) {
        return aGeod.elevation;
    } else {
        return -1;
    }
}

var calculate_imp_time = func(aGeod, aAircraftPosition, aElevation, aSpeed_fps) {
    if (aGeod != nil and aElevation > 0.0) {
        var end = geo.Coord.new(aAircraftPosition);
        end.set_latlon(aGeod.lat, aGeod.lon, aElevation);
        var dist = aAircraftPosition.direct_distance_to(end) * M2FT;
        var time_to_impact = dist / aSpeed_fps;
        if (time_to_impact < 0.1) time_to_impact = 0.1;
        return time_to_impact;
    } else {
        return -1;
    }
}

var setIntensty_calc_lag = func(aIntensity_calc,intensity_calc_lag_incr,intensity_calc_lag_dec,speed_cas) {
    if (speed_cas > 250.0) {
        aIntensity_calc = aIntensity_calc * (250.0 / speed_cas);
    }
    var incr = intensity_calc_lag_incr * delta_time;
    var dec = intensity_calc_lag_dec * delta_time;
    if (aIntensity_calc > (intensity_calc_lag + incr / 2)) {
        intensity_calc_lag = intensity_calc_lag + intensity_calc_lag_incr * delta_time;
        intensity_calc_lag_versus = 1;
    } else if (aIntensity_calc < (intensity_calc_lag - dec / 2)) {
        intensity_calc_lag = intensity_calc_lag - intensity_calc_lag_dec * delta_time;
        intensity_calc_lag_versus = -1;
    }
    if (intensity_calc_lag <= 0.05) {
        intensity_calc_lag = 0.0;
        intensity_calc_lag_versus = 0;
    }
}


var main = func() {
    
    print("pilot_impact_control.nas load module");
    
}


var unload = func() {
    
    print("pilot_impact_control.nas unload module");

}


var analyze_imp_time = func() {
    
    testing_log_active = getprop("sim/G91/testing/log");
    if (testing_log_active == nil) testing_log_active = 0;
    #// Debug only:
    #// testing_log_active = 4;
    
    #
    # Min time for start the anti-impact procedure
    #
    var speed_cas_on_air = getprop("fdm/jsbsim/systems/autopilot/speed-cas-on-air");
    if (speed_cas_on_air == nil) speed_cas_on_air = 250.0;
    imp_medium_time = getprop("fdm/jsbsim/systems/autopilot/gui/impact-medium-time") * (complex_factor + 1.5 * (speed_cas_on_air / 250.0 - 1.0));
    speed_horz_fps = getprop("fdm/jsbsim/systems/autopilot/velocity-on-ground-fps-lag");
    speed_horz_mph = getprop("fdm/jsbsim/systems/autopilot/velocity-on-ground-mph-lag");
    
    #
    # Min altitude
    #
    imp_min_z_ft = getprop("fdm/jsbsim/systems/autopilot/altitude-QFE-ft-mod");
    var imp_min_z_ft_delta = 10.0 * delta_time;
    if ((imp_min_z_ft - 10) > imp_min_z_ft_lag) {
        imp_min_z_ft_lag = imp_min_z_ft_lag + imp_min_z_ft_delta;
    } else if ((imp_min_z_ft + 10) < imp_min_z_ft_lag) {
        imp_min_z_ft_lag = imp_min_z_ft_lag - imp_min_z_ft_delta;
    } 
    setprop("fdm/jsbsim/systems/autopilot/gui/impact-min-z-ft-mod",imp_min_z_ft_lag);
    
    #
    # Calculate aircraft position and velocity vector
    #
    pitch_angle_deg = getprop("fdm/jsbsim/systems/autopilot/pitch-angle-absolute-deg-lag");
    var pitch_ang_tan = math.tan(pitch_angle_deg * 0.0174533);
    
    speed_down_fps  = getprop("velocities/speed-down-fps");
    speed_fps = getprop("fdm/jsbsim/systems/autopilot/speed-true-fps");
    var heading = getprop("fdm/jsbsim/systems/autopilot/heading-true-deg");
    var imp_pitch_alpha = 0.0;
    
    #
    # Situation analisys by T0 (orizontal) T1 and T2
    #
    
    var aircraftPosition = geo.aircraft_position();
    var h_airplane_sl_ft = getprop("fdm/jsbsim/position/h-sl-ft");
    
    var radar_elv_n = 13;
    var radar_elv_geod = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0];
    var radar_elv_sum_der = 0.0;
    var complex_factor_ar = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0];
    var complex_factor_avg = 0.0;
    var radar_elv_prec = 0.0;
    var radar_elv_Hsl_ft = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0];
    var radar_elv_is_valid = [0,0,0,0,0,0,0,0,0,0,0,0,0];
    var radar_elv_time = [0.5,0.5,1,2,3,5,10,15,20,25,30,60,120];
    var radar_elv_all_valid = 1;
    var radar_elv_h_T0_ft = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0];
    var radar_elv_h_T1_ft = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0];
    var radar_elv_h_T2_ft = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0];
    var radar_elv_h_T3_ft = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0];
    var radar_elv_h_T4_ft = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0];
    var radar_prc_T0_sign = -1;
    var radar_prc_T1_sign = -1;
    var radar_prc_T2_sign = -1;
    var radar_prc_T3_sign = -1;
    var radar_prc_T4_sign = -1;
    var radar_chn_T0_sign = -1;
    var radar_chn_T1_sign = -1;
    var radar_chn_T2_sign = -1;
    var radar_chn_T3_sign = -1;
    var radar_chn_T4_sign = -1;
    var radar_elv_T0_max = -999999.0;
    var radar_elv_T1_max = -999999.0;
    var radar_elv_T2_max = -999999.0;
    var radar_elv_T3_max = -999999.0;
    var radar_elv_T4_max = -999999.0;
    var radar_elv_T4_min = 999999.0;
    var imp_time_T0 = 0.0;
    var imp_time_T1 = 0.0;
    var imp_time_T2 = 0.0;
    var imp_time_T3 = 0.0;
    var imp_time_T4 = 0.0;
    
    var radar_min_alpha_tan = 0.0;
    if (speed_horz_fps > 1.0) radar_min_alpha_tan = getprop("/position/altitude-agl-ft") / (speed_horz_fps * imp_medium_time);
    
    for (var i = 1; i < radar_elv_n; i = i + 1) {
        radar_elv_geod[i] = radar_elv_beam(aircraftPosition,heading,speed_horz_fps,radar_elv_time[i]);
        if (i == 1) radar_elv_geod[0] = radar_elv_geod[1];
        if (radar_elv_geod[i] != nil) {
            radar_elv_is_valid[i] = 1;
            var h = geo.elevation(radar_elv_geod[i].lat(),radar_elv_geod[i].lon());
            if (h != nil) {
                radar_elv_Hsl_ft[i] = h / FT2M + imp_min_z_ft_lag;
                if (i >= 2) {
                    radar_elv_sum_der = radar_elv_sum_der + math.abs((h - radar_elv_prec) / (radar_elv_time[i]-radar_elv_time[i-1]));
                }
                radar_elv_prec = h;
                #// Calculate T0 
                #// Height of the point placed on the surface of the ground that meets a horizontal line
                radar_elv_h_T0_ft[i] = radar_elv_Hsl_ft[i] - h_airplane_sl_ft;
                if (radar_chn_T0_sign == -1) {
                    if (radar_elv_h_T0_ft[i] > 0) {
                        if (radar_prc_T0_sign < 0) radar_chn_T0_sign = i;
                    }
                    if (radar_elv_h_T0_ft[i] > radar_elv_T0_max and radar_elv_time[i] <= imp_medium_time) radar_elv_T0_max = radar_elv_h_T0_ft[i];
                }
                #// Calculate T1
                #// Height of the point placed on the surface of the ground that meets a line coinciding with the trajectory of the aircraft
                radar_elv_h_T1_ft[i] = radar_elv_Hsl_ft[i] - (h_airplane_sl_ft + (radar_elv_time[i] * speed_horz_fps * pitch_ang_tan));
                if (radar_chn_T1_sign == -1) {
                    if (radar_elv_h_T1_ft[i] > 0) {
                        if (radar_prc_T1_sign < 0) radar_chn_T1_sign = i;
                    }
                    if (radar_elv_h_T1_ft[i] > radar_elv_T1_max and radar_elv_time[i] <= imp_medium_time) radar_elv_T1_max = radar_elv_h_T1_ft[i];
                }
                #// Calculate T2 (radar_min_alpha_tan)
                radar_elv_h_T2_ft[i] = radar_elv_Hsl_ft[i] - (h_airplane_sl_ft + (radar_elv_time[i] * speed_horz_fps * -1.0 * radar_min_alpha_tan));
                if (radar_chn_T2_sign == -1) {
                    if (radar_elv_h_T2_ft[i] > 0) {
                        if (radar_prc_T2_sign < 0) radar_chn_T2_sign = i;
                    }
                    if (radar_elv_h_T2_ft[i] > radar_elv_T2_max and radar_elv_time[i] <= imp_medium_time) radar_elv_T2_max = radar_elv_h_T2_ft[i];
                }
                #// Calculate T3 (+20 deg)
                #// Height of the point placed on the surface of the ground that meets a line inclined 20 degrees to the sky
                radar_elv_h_T3_ft[i] = radar_elv_Hsl_ft[i] - (h_airplane_sl_ft + (radar_elv_time[i] * speed_horz_fps * 0.1));
                if (radar_chn_T3_sign == -1) {
                    if (radar_elv_h_T3_ft[i] > 0) {
                        if (radar_prc_T3_sign < 0) radar_chn_T3_sign = i;
                    }
                    if (radar_elv_h_T3_ft[i] > radar_elv_T3_max and radar_elv_time[i] <= imp_medium_time) radar_elv_T3_max = radar_elv_h_T3_ft[i];
                }
                #// Calculate T4 (-20 deg)
                #// Height of the point placed on the surface of the ground that meets a line inclined 20 degrees to the ground
                radar_elv_h_T4_ft[i] = radar_elv_Hsl_ft[i] - (h_airplane_sl_ft + (radar_elv_time[i] * speed_horz_fps * -0.364));
                if (radar_chn_T4_sign == -1) {
                    if (radar_elv_h_T4_ft[i] > 0) {
                        if (radar_prc_T4_sign < 0) radar_chn_T4_sign = i;
                    }
                    if (radar_elv_h_T4_ft[i] >= radar_elv_T4_max and radar_elv_time[i] <= imp_medium_time) radar_elv_T4_max = radar_elv_h_T4_ft[i];
                    if (radar_elv_h_T4_ft[i] >= 0.0 and radar_elv_h_T4_ft[i] < radar_elv_T4_min) radar_elv_T4_min = radar_elv_h_T4_ft[i];
                }
                #// Calculate complex factor
                complex_factor_ar[i] = 1.0 + 0.5 * math.ln(1.0 + math.abs(radar_elv_sum_der / 20.0));
                complex_factor_avg = complex_factor_avg + complex_factor_ar[i];
                if (testing_log_active >= 3 and timeStepSecond == 1) {
                    print("# Radar"
                        ,sprintf(" H: %#5d",h / FT2M)
                        ,sprintf(" i: %#2d",i)
                        ,sprintf(" T: %#3d",radar_elv_time[i])
                        ,sprintf(" Elv h: %#5d",radar_elv_Hsl_ft[i])
                        ,sprintf(" HAir: %#5d",h_airplane_sl_ft)
                        ,sprintf(" MT: %#3d",imp_medium_time)
                        ,sprintf(" Dif: %#6d",radar_elv_h_T0_ft[i])
                        ,sprintf(" | T1 %#6d",radar_elv_h_T1_ft[i])
                        ,sprintf(" | T2 %#6d",radar_elv_h_T2_ft[i])
                        ,sprintf(" | T3 %#6d",radar_elv_h_T3_ft[i])
                        ,sprintf(" | T4 %#6d",radar_elv_h_T4_ft[i])
                        ,sprintf(" Sg: %#2d",radar_prc_T0_sign)
                        ,sprintf(" : %#3d",radar_chn_T0_sign )
                        ,sprintf(" | T1 %#2d",radar_prc_T1_sign )
                        ,sprintf(" : %#3d",radar_chn_T1_sign )
                        ,sprintf(" | T2 %#2d",radar_prc_T2_sign )
                        ,sprintf(" : %#3d",radar_chn_T2_sign )
                        ,sprintf(" | T3 %#2d",radar_prc_T3_sign )
                        ,sprintf(" : %#3d",radar_chn_T3_sign )
                        ,sprintf(" | T4 %#2d",radar_prc_T4_sign )
                        ,sprintf(" : %#3d",radar_chn_T4_sign )
                        ,sprintf(" Elv M: %#6.0f",radar_elv_T0_max)
                        ,sprintf(" | T1 %#6d",radar_elv_T1_max)
                        ,sprintf(" | T2 %#6d",radar_elv_T2_max)
                        ,sprintf(" | T3 %#6d",radar_elv_T3_max)
                        ,sprintf(" | T4 %#6d",radar_elv_T4_max)
                        ,sprintf(" DS: %#5d",radar_elv_sum_der)
                        ,sprintf(" Cmp: %#1.2f",complex_factor_ar[i])
                        ,sprintf(" | %#2.2f",complex_factor_avg / i)
                    );
                }
            } else {
                radar_elv_is_valid[i] = 0;
                radar_elv_all_valid = 0;
            }
        } else {
            radar_elv_is_valid[i] = 0;
            radar_elv_all_valid = 0;
        }
    }

    #// ADV for complex_factor
    var complex_factor_dif = complex_factor_avg / 12.0;
    complex_factor_adv.insert(-1,complex_factor_dif);
    if (complex_factor_adv.size() > 20) {
        complex_factor_dif = complex_factor_dif - complex_factor_adv.pop(0);;
    }
    complex_factor_acc = complex_factor_acc + complex_factor_dif;
    complex_factor_target = complex_factor_acc / complex_factor_adv.size();
    if (complex_factor_target < 1.0) complex_factor_target = 1.0;
    if ((complex_factor - 0.05) > complex_factor_target) {
        complex_factor = complex_factor - 0.01;
    } else if ((complex_factor + 0.1) < complex_factor_target) {
        complex_factor = complex_factor + 0.1;
    }

    var elevation = 0.0;
    var elevation_max = 0.0;
    var intensity_T0 = 0.0;
    var intensity_T1 = 0.0;
    var intensity_T2 = 0.0;
    var intensity_T3 = 0.0;
    var intensity_T4 = 0.0;
    var intensity = 0.0;
    var factor_lag = 0.0;

    if (radar_chn_T0_sign >= 1) {
        imp_time_T0 = radar_elv_time[radar_chn_T0_sign];
        if (imp_time_T0 <= (imp_medium_time)) {
            intensity_T0 = 1.0 * (0.5 + math.log10(imp_medium_time / (imp_time_T0 * 0.8))) * complex_factor;
        }
        elevation = radar_elv_T0_max;
    }
    if ((intensity_T0_lag - 0.1) > intensity_T0) {
        intensity_T0_lag = intensity_T0_lag - 1.0 * delta_time;
    } else if ((intensity_T0_lag + 0.1) < intensity_T0) {
        intensity_T0_lag = intensity_T0_lag + 0.2 * delta_time;
    }
    if (elevation_max < elevation and imp_time_T0 < imp_medium_time) {
        elevation_max = elevation;
    }
    
    if (radar_chn_T1_sign >= 1) {
        imp_time_T1 = radar_elv_time[radar_chn_T1_sign];
        if (imp_time_T1 <= imp_medium_time) {
            intensity_T1 = 2.0 * ((0.5 + math.log10(imp_medium_time / (imp_time_T1 * 0.8))) * complex_factor);
        }
        elevation = radar_elv_T1_max;
        if (elevation_max < elevation and imp_time_T1 < imp_medium_time) {
            elevation_max = elevation;
        }
    }
    if ((intensity_T1_lag - 0.1) > intensity_T1) {
        intensity_T1_lag = intensity_T1_lag - 1.0 * delta_time;
    } else if ((intensity_T1_lag + 0.1) < intensity_T1) {
        intensity_T1_lag = intensity_T1_lag + 0.2 * delta_time;
    }
    
    var factor_t2 = 1.0;
    if (intensity_T1 <= 0.1) {
        if (intensity_T0 <= 0.1) {
            factor_t2 = -2.0;
        } else {
            factor_t2 = -1.0;
        }
    }
    
    if (radar_chn_T2_sign >= 1) {
        imp_time_T2 = radar_elv_time[radar_chn_T2_sign];
        if (imp_time_T2 <= imp_medium_time) {
            intensity_T2 = factor_t2 * (0.5 + math.log10(imp_medium_time / imp_time_T2)) * complex_factor;
        }
        elevation = radar_elv_T2_max;
    }
    if ((intensity_T2_lag - 0.1) > intensity_T2) {
        intensity_T2_lag = intensity_T2_lag - 0.2 * delta_time;
    } else if ((intensity_T2_lag + 0.1) < intensity_T2) {
        intensity_T2_lag = intensity_T2_lag + 0.2 * delta_time;
    }
    
    if (elevation_max < elevation and imp_time_T2 < imp_medium_time) {
        elevation_max = elevation;
    }
    
    if (radar_chn_T3_sign >= 1) {
        imp_time_T3 = radar_elv_time[radar_chn_T3_sign];
        if (imp_time_T3 <= imp_medium_time) {
            intensity_T3 = 1.4 * (0.5 + math.log10(imp_medium_time / (imp_time_T3 * 0.8)));
        }
        elevation = radar_elv_T3_max;
    }
    if ((intensity_T3_lag - 0.1) > intensity_T3) {
        # intensity_T3_lag = intensity_T3_lag - 0.3 * delta_time;
    } else if ((intensity_T3_lag + 0.1) < intensity_T3) {
        # intensity_T3_lag = intensity_T3_lag + 0.2 * delta_time;
    }
    if ((intensity_T3_lag - 0.1) > intensity_T3) {
        intensity_T3_lag = intensity_T3_lag - 0.06 * delta_time;
    } else if ((intensity_T3_lag + 0.1) < intensity_T3) {
        intensity_T3_lag = intensity_T3_lag + 0.04 * delta_time;
    }

    if (elevation_max < elevation and imp_time_T3 < ((imp_medium_time / 5.0) * imp_medium_time)) {
        elevation_max = elevation;
    }
    
    if (radar_chn_T4_sign >= 1 and radar_elv_T4_min < 0.75 * imp_min_z_ft ) {
        imp_time_T4 = radar_elv_time[radar_chn_T4_sign];
        if (imp_time_T4 <= imp_medium_time) {
            intensity_T4 = 1.0 * (0.5 + math.log10(imp_medium_time / imp_time_T4)) * complex_factor;
        }
        elevation = radar_elv_T4_max;
        
        if (elevation_max < elevation and imp_time_T4 < ((imp_medium_time / 2.0) * imp_medium_time)) {
            elevation_max = elevation;
        }
    }
    if ((intensity_T4_lag - 0.1) > intensity_T4) {
        intensity_T4_lag = intensity_T4_lag - 0.1 * delta_time;
    } else if ((intensity_T4_lag + 0.1) < intensity_T4) {
        intensity_T4_lag = intensity_T4_lag + 0.2 * delta_time;
    }
    
    if (intensity_T0_lag < 0.8) {
        setprop("fdm/jsbsim/systems/autopilot/altitude-QFE-impact-elev-to-oriz",1);
    } else {
        setprop("fdm/jsbsim/systems/autopilot/altitude-QFE-impact-elev-to-oriz",0);
    }
    
    setprop("fdm/jsbsim/systems/autopilot/altitude-QFE-impact-elev-complex-factor",complex_factor);
    
    intensity = (intensity_T0_lag + intensity_T1_lag + intensity_T2_lag + intensity_T3_lag + intensity_T4_lag) * complex_factor / 8.0;
    if (intensity < 0.0 or intensity_T0_lag < 0.1) intensity = 0.0;
    #// Intensity filter, is very importan, the frist costant define the time advance by the sensivity increment the second the intensity reduction
    # 1.5 - 0.7
    intensity = (complex_factor / 1.2) * math.atan(intensity / 0.5);
    
    # setIntensty_calc_lag(intensity, 0.3 * complex_factor,0.05 * complex_factor,speed_cas_on_air);
    setIntensty_calc_lag(intensity, 0.3 * complex_factor,0.05 * complex_factor,speed_cas_on_air);
    
    if (imp_cnt_active == 1) {
        setprop("fdm/jsbsim/systems/autopilot/altitude-QFE-impact-elev-ft",elevation_max + h_airplane_sl_ft + imp_min_z_ft_lag);
        setprop("fdm/jsbsim/systems/autopilot/altitude-QFE-impact-elev-intensity",intensity_calc_lag);
    } else {
        setprop("fdm/jsbsim/systems/autopilot/altitude-QFE-impact-elev-ft",0.0);
        setprop("fdm/jsbsim/systems/autopilot/altitude-QFE-impact-elev-intensity",0.0);
    }
    
    if (testing_log_active == 2 and timeStepSecond == 1) {
        print("## Impact ctl: "
              ,sprintf(" Altitude-QFE %5d ",elevation_max)
              ,sprintf(" | %5d",h_airplane_sl_ft)
              ,sprintf(" | %5d",imp_min_z_ft_lag)
              ,sprintf(" | %5d",elevation_max + h_airplane_sl_ft + imp_min_z_ft_lag)
              ,sprintf(" | %5d",radar_elv_T4_min)
              ,sprintf(" Speed: %#4d",speed_horz_fps)
              ,sprintf(" intensity: %2.2f", intensity)
              ,sprintf(" ( %4.2f |",intensity_T0_lag)
              ,sprintf(" %4.2f |",intensity_T1_lag)
              ,sprintf(" %4.2f |",intensity_T2_lag)
              ,sprintf(" %4.2f |",intensity_T3_lag)
              ,sprintf(" %4.2f |",intensity_T4_lag)
              ,sprintf(" lag: %2.2f )",intensity_calc_lag)
              ,sprintf(" imp_medium_time: %2.2f",imp_medium_time)
              ,sprintf(" neutre: %2.1f",neutre_lag)
              ,sprintf(" | %2.1f",factor_neutre)
              ,sprintf(" | %2.1f",neutre_lag_active)
              ,sprintf(" | %3d",neutre_lag_n)
              ,sprintf(" complex: %2.1f",complex_factor)
              ,sprintf(" | %5.0f",radar_elv_sum_der)
        );
    }
    if (testing_log_active >= 1) {
        setprop("fdm/jsbsim/systems/autopilot/pilot-impact-control-t0",intensity_T0_lag);
        setprop("fdm/jsbsim/systems/autopilot/pilot-impact-control-t1",intensity_T1_lag);
        setprop("fdm/jsbsim/systems/autopilot/pilot-impact-control-t2",intensity_T2_lag);
        setprop("fdm/jsbsim/systems/autopilot/pilot-impact-control-t3",intensity_T3_lag);
        setprop("fdm/jsbsim/systems/autopilot/pilot-impact-control-t4",intensity_T4_lag);
    }
    
    #// Message builder
    if (getprop("fdm/jsbsim/systems/autopilot/altitude-type-selector") == 3.0) {
        setprop("fdm/jsbsim/systems/autopilot/altitude-QFE-set-active-text","Auto QFE stop");
    } else if (getprop("systems/autopilot/altitude-type-selector") == 2.0) {
        setprop("fdm/jsbsim/systems/autopilot/altitude-QFE-set-active-text","Auto QFE on");
    } else {
        setprop("fdm/jsbsim/systems/autopilot/altitude-QFE-set-active-text","         ");
    }
    
}


var pilot_imp_control = func() {
    
    imp_cnt_active = getprop("fdm/jsbsim/systems/autopilot/gui/impact-control-active");
    analyze_imp_time();
    
    if (imp_cnt_active == 0) {
        timeStepDivisor = 1;
    } else {
        if (intensity_calc_lag < 0.3) {
            timeStepDivisor = 2;
        } else {
            timeStepDivisor = 5;
        }
    }
    delta_time = timeStep / timeStepDivisor;
    pilot_imp_controlTimer.restart(delta_time);
    if (timeStepSecond == 1) timeStepSecond = 0;

}


var pilot_imp_controlTimer = maketimer(delta_time, pilot_imp_control);
pilot_imp_controlTimer.singleShot = 1;
pilot_imp_controlTimer.start();

var pilot_imp_timerLog = maketimer(1, func() {timeStepSecond = 1;});
pilot_imp_timerLog.start();
