# This function calculates the profit made by a marginal (5th percentile) fisher in an average year and returns profits. 
# The function is built to be used in a root-finding method to calculate what variable costs will lead to a fishing 
# fleet at equilibrium (no one leaving or entering the fishery). There are some print statement to help with tuning.
#
# It currently handles only single fishery fleets, no multi-fishery participation.
# One idea: instead of calculating in the average year, which will lead to average profits > 0 because profits have a 
# positive skew (profits have a negative limit in bad years because people stop fishing, but no positive limit in bumper 
# years), calculate average profit across distribution of years. 
calc_var_cost <- function(log_avg_cost_per_trip, cost_cv, recruits, wt_at_rec, fishing_season, in_season_dpltn, 
                          fleet_size, fixed_costs, catchability, price, tac = NA) {
  # avg_cost_per_trip <- exp(log_cost_per_trip)
  quantiles <- seq(1/(fleet_size+1), fleet_size/(fleet_size+1), length.out = fleet_size)
  cost_per_trip <- qlnorm(quantiles, log_avg_cost_per_trip - cost_cv^2/2, cost_cv)
  N <- numeric(wks_per_yr)
  N[1] <- recruits
  variable_costs <- revenue <- numeric(fleet_size)
  Catch <- matrix(0, nrow = wks_per_yr, ncol = fleet_size)
  if(length(price) == 1) {
    price_vec <- rep(price, wks_per_yr+1)
  } else {
    price_vec <- numeric(wks_per_yr+1)
    price_vec[1] <- 1#price[1] - price[2] * recruits * wt_at_rec * catchability * fleet_size
  }
  
  for(wk in 1:wks_per_yr) { 
    exp_profit <- N[wk] * wt_at_rec * price_vec[wk] * catchability * fishing_season[wk]  - cost_per_trip
    did_fish <- exp_profit >= 0
    variable_costs <- variable_costs + did_fish * cost_per_trip
    Catch[wk,] <- did_fish * catchability * N[wk]
    if(length(price) > 1) {
      if(sum(Catch[wk,]) > 0.1) {
        price_vec[wk+1] <- 1
      } else{
        price_vec[wk+1] <- price[1] - price[2] * sum(Catch[wk,])
      }
    }
    revenue <- revenue + Catch[wk,] * wt_at_rec * price_vec[wk+1]
    
    if(wk < wks_per_yr) {
      N[wk+1] <- ifelse(in_season_dpltn,
                        N[wk] - sum(Catch[wk,]),
                        N[wk])
    }
    if(!is.na(tac)) {
      if(sum(Catch) > tac * N[1]) {
        print('TAC reached!')
        break
      }
    }
  }
  print(sum(Catch))
  # print(price_vec)
  print(paste(mean(variable_costs), fixed_costs))
  # Want entry/exit at equilibrium, new fisher should expect 0 net profits. 
  # New fisher would have higher than average costs though, so set profit = 0 for 95th percentile variable cost fisher 
  marginal_fisher <- round(.95 * fleet_size)
  profit <- revenue[marginal_fisher] - variable_costs[marginal_fisher] - fixed_costs
  # profit <- sum(revenue - variable_costs) - fixed_costs*fleet_size 
  # print(paste('avg profit is', profit))
  return(profit)
}


# This function sets up the objects to be filled in the simulations. Returns a list of abundance (includes simulated 
# pre-season recruitment, remaining weeks to be filled), catch (empty), profit (empty), weights (simulated), 
# salmon TACs (based on the simulated recruitment), ship-specific variable costs (simulated, constant across years), 
# number of ships from the multi-fishery fleet fishing for crab (empty)
set_up_objects <- function(sim_pars, seed) {
  set.seed(seed)
  list2env(sim_pars, sys.frame(sys.nframe()))
  profits <- array(-t(fleet_permits) %*% fixed_costs, dim = c(nfleets, nships, nyrs),  
                   dimnames = list(fleet = fleets, ship = NULL, yr = NULL)) %>%
    aperm(c(2,3,1))
  
  Catch <- array(0, dim = c(npops, nyrs, wks_per_yr, nfleets), 
                 dimnames = list(spp = spp.names, yr = NULL, wk = NULL, fleet = fleets))
  
  N <- array(0, dim = c(npops, nyrs, wks_per_yr), dimnames = list(spp = spp.names, yr = NULL, wk = NULL))
  N[,,1] <- rmvnorm(nyrs, mean = log(avg_rec) - recruit_cv^2/2, sigma = recruit_cv * diag(npops)) %>%
    t %>%
    exp

  wt_at_rec <- rmvnorm(nyrs, mean = log(avg_wt) - weight_cv^2/2, sigma = weight_cv * diag(npops)) %>% 
    t %>%
    exp
  dimnames(wt_at_rec) <- list(spp = spp.names, yr = NULL)
  # Right now: white noise, independence between stocks. 
  # To do: correlation in time and between stocks.
  
  salmon_tac <- N['salmon',,1] * salmon_tac_rule

  # simulate cost per trip for each ship in each fleet
  cost_by_ship <- array(0, dim = c(nships, nfleets, npops), 
                        dimnames = list(ships = NULL, fleet = fleets, spp = spp.names))
  sigma_mat <- matrix(cost_corr*cost_cv^2, nrow = npops, ncol = npops)
  diag(sigma_mat) <- cost_cv^2
  
  for(fleet in 1:nfleets) {
    fleet_permits_TF <- as.logical(fleet_permits[,fleet])
    cost_by_ship[1:ships_per_fleet[fleet], fleet,] <- exp(rmvnorm(ships_per_fleet[fleet],
                                                                  mean = log(cost_per_trip) - cost_cv^2/2,
                                                                  sigma = sigma_mat)) %*%
      diag(fleet_permits_TF)
  }
  cost_by_ship[cost_by_ship==0] <- NA
  
  n_crab_ships <- array(0, dim = c(wks_per_yr, nyrs), 
                        dimnames = list(wk = NULL, yr = NULL))
  out.list <- list(profits = profits, Catch = Catch, N = N, wt_at_rec = wt_at_rec, 
                   salmon_tac = salmon_tac, cost_by_ship = cost_by_ship, n_crab_ships = n_crab_ships)
  return(out.list)
}


# This function simulates the fleets and populations for a bunch of years with weekly time steps. Returns catch, profits, 
# recruitment, number of ships in the multi-fishery fleet fishing for crab each week of each year
run_sim <- function(sim_pars, seed){
  setup.ls <- set_up_objects(sim_pars, seed)
  list2env(setup.ls, sys.frame(sys.nframe()))
  list2env(sim_pars, sys.frame(sys.nframe()))
  
  this_week_profit <- matrix(0, nrow = nships, ncol = nfleets)
  for(yr in 1:nyrs) {
    temp_catchability <- catchability
    price_mat <- matrix(price, nrow = wks_per_yr+1, ncol = npops, byrow = TRUE,
                        dimnames = list(wk=NULL, spp=spp.names))
    for(wk in 1:wks_per_yr){
      if(sum(pop_seasons[,wk]) > 0) {
        exp_rev <- array(N[,yr,wk] * wt_at_rec[,yr] * temp_catchability * price_mat[wk,] * pop_seasons[,wk], 
                         dim=c(npops, nships, nfleets)) %>% 
          aperm(perm = c(2,3,1))
        # If out of legal season, expected revenue = 0. 
        # exp_rev does *not* care whether a fleet has a permit though! (That's in exp_profit)
        
        exp_profit <- exp_rev - cost_by_ship
        
        best_spp <- apply(exp_profit, 2, getBestSpp)
        # returns index of most profitable stock for each ship, or NA if no stock is profitable.
        
        if(any(!is.na(best_spp))) {
          ships_per_stock <- apply(best_spp, 2, tabulate, nbins = npops)
        } else {
          ships_per_stock <- matrix(0, nrow = npops, ncol = nfleets)
        }
        # counts up number of ships fishing each stock
        n_crab_ships[wk,yr] <- ships_per_stock[2,2]
        Catch[,yr,wk,] <- ships_per_stock * temp_catchability * N[,yr,wk]
        
        # Adjust crab stuff because it has a demand function. Too many things are hard-coded right now.
        if(sum(Catch['crab',yr,wk,c('crab','both')]) > 0.1) {
          price_mat[wk+1,'crab'] <- 1
        } else {
          price_mat[wk+1,'crab'] <- 2 - 10 * sum(Catch['crab',yr,wk,c('crab','both')]) * wt_at_rec['crab',yr]
        }
        
        actual_crab_rev <- N['crab',yr,wk] * wt_at_rec['crab',yr] * temp_catchability['crab'] *
          price_mat[wk+1,'crab'] * pop_seasons['crab',wk]
        actual_profit <- exp_profit
        actual_profit[,,'crab'] <- actual_crab_rev - cost_by_ship[,,'crab']
        
        for(fleet in 1:nfleets) {
          this_week_profit[,fleet] <- actual_profit[cbind(1:nships, fleet, best_spp[,fleet])]
        }
        this_week_profit[is.na(this_week_profit)] <- 0
        
        profits[,yr,] <- profits[,yr,] + this_week_profit
        # actual profits are for the stock with max expected profit, if max is > 0. 
        
      } else {
        Catch[,yr,wk,] <- 0
      }
      
      if(wk < wks_per_yr) {
        N[,yr,wk+1] <- N[,yr,wk] - apply(Catch[,yr,wk,], 1, sum)
      }
      if(sum(Catch['salmon',yr,,]) >= salmon_tac[yr]) {
        # if you hit the salmon TAC, set catchability to 0
        temp_catchability['salmon'] <- 0
        print(paste('salmon TAC engaged in week', wk, 'of year', yr))
      }
    }
  }
  
  out.list <- list(Catch = Catch, profits = profits, n_crab_ships = n_crab_ships, recruitment = N[,,1])
  return(out.list)
}

