################################################
###  BMKR code for CU mixtures workshop      ###
###  developed by Katrina Devick             ### 
###  last updated: 5/17/19                  ###
###  Changed POP groups                      ###
################################################


## load required libraries 
library(bkmr)
library(corrplot)
library(ggplot2)


################################################
###         Data Manipulation                ###
################################################


## read in data and only consider complete data 
## this drops 327 individuals, but BKMR does not handle missing data
nhanes <- na.omit(read.csv("Data/studypop.csv"))

## center/scale continous covariates and create indicators for categorical covariates
nhanes$age_z         <- scale(nhanes$age_cent)         ## center and scale age
nhanes$agez_sq       <- nhanes$age_z^2                 ## square this age variable
nhanes$bmicat2       <- as.numeric(nhanes$bmi_cat3==2) ## 25 <= BMI < 30
nhanes$bmicat3       <- as.numeric(nhanes$bmi_cat3==3) ## BMI >= 30 (BMI < 25 is the reference)
nhanes$educat1       <- as.numeric(nhanes$edu_cat==1)  ## no high school diploma
nhanes$educat3       <- as.numeric(nhanes$edu_cat==3)  ## some college or AA degree
nhanes$educat4       <- as.numeric(nhanes$edu_cat==4)  ## college grad or above (reference is high schol grad/GED or equivalent)
nhanes$otherhispanic <- as.numeric(nhanes$race_cat==1) ## other Hispanic or other race - including multi-racial
nhanes$mexamerican   <- as.numeric(nhanes$race_cat==2) ## Mexican American 
nhanes$black         <- as.numeric(nhanes$race_cat==3) ## non-Hispanic Black (non-Hispanic White as reference group)
nhanes$wbcc_z        <- scale(nhanes$LBXWBCSI)
nhanes$lymphocytes_z <- scale(nhanes$LBXLYPCT)
nhanes$monocytes_z   <- scale(nhanes$LBXMOPCT)
nhanes$neutrophils_z <- scale(nhanes$LBXNEPCT)
nhanes$eosinophils_z <- scale(nhanes$LBXEOPCT)
nhanes$basophils_z   <- scale(nhanes$LBXBAPCT)
nhanes$lncotinine_z  <- scale(nhanes$ln_lbxcot)         ## to access smoking status, scaled ln cotinine levels


## our y variable - ln transformed and scaled mean telomere length
lnLTL_z <- scale(log(nhanes$TELOMEAN)) 

## our Z matrix
mixture <- with(nhanes, cbind(LBX074LA, LBX099LA, LBX118LA, LBX138LA, LBX153LA, LBX170LA, LBX180LA, LBX187LA, 
                              LBX194LA, LBXHXCLA, LBXPCBLA,
                              LBXD03LA, LBXD05LA, LBXD07LA,
                              LBXF03LA, LBXF04LA, LBXF05LA, LBXF08LA)) 
lnmixture   <- apply(mixture, 2, log)
lnmixture_z <- scale(lnmixture)
colnames(lnmixture_z) <- c(paste0("PCB",c(74, 99, 118, 138, 153, 170, 180, 187, 194, 169, 126)), 
                           paste0("Dioxin",1:3), paste0("Furan",1:4)) 

## our X matrix
covariates <- with(nhanes, cbind(age_z, agez_sq, male, bmicat2, bmicat3, educat1, educat3, educat4, 
                                 otherhispanic, mexamerican, black, wbcc_z, lymphocytes_z, monocytes_z, 
                                 neutrophils_z, eosinophils_z, basophils_z, lncotinine_z)) 

### create knots matrix for Gaussian predictive process (to speed up BKMR with large datasets)
set.seed(10)
knots100     <- fields::cover.design(lnmixture_z, nd = 100)$design
save(knots100, file="Supervised/BKMR/saved_model/NHANES_knots100.RData")

################################################
###         Fit Models                       ###
################################################

#load("./BKMR/saved_model/NHANES_knots100.RData")

##### fit BKMR models WITH Gaussian predictive process using 100 knots

### Group VS fit with all exposures using GPP and 100 knots 
set.seed(1000)

fit_gvs_knots100 <-  kmbayes(y=lnLTL_z, Z=lnmixture_z, X=covariates, iter=100000, verbose=TRUE, varsel=TRUE, 
                             groups=c(rep(1,times=2), 2, rep(1,times=6), rep(3,times=2),rep(2,times=7)), knots=knots100)

summary(fit_gvs_knots100)
save(fit_gvs_knots100,file="Supervised/BKMR/saved_model/bkmr_NHANES_gvs_knots100.RData")

## obtain posterior inclusion probabilities (PIPs)
ExtractPIPs(fit_gvs_knots100)

##############################################
###        PLOTS                           ###
##############################################

#load("Supervised/BKMR/saved_model/bkmr_NHANES_gvs_knots100.RData")

### correlation matrix
cor.Z <- cor(lnmixture_z, use="complete.obs")

pdf(file="Supervised/BKMR/figures_pdf/cor_nhanes.pdf", width=12, height=12)
corrplot.mixed(cor.Z, upper = "ellipse", lower.col="black")
dev.off()

###############################################

### change this for each model you fit and then rerun the code from here to the bottom
modeltoplot      <- fit_gvs_knots100   ## name of model object
modeltoplot.name <- "fit_gvs_knots100" ## name of model for saving purposes
plot.name        <- "gvs_knots100"     ## part that changed in plot name 
Z                <- lnmixture_z        ## Z matrix to match what was used in model

### values to keep after burnin/thin
sel<-seq(50001,100000,by=50)

### access convergence with traceplots 
TracePlot(fit = modeltoplot, par = "beta", sel=sel)
TracePlot(fit = modeltoplot, par = "sigsq.eps", sel=sel)

par(mfrow=c(2,2))
TracePlot(fit = modeltoplot, par = "r", comp = 1, sel=sel)
TracePlot(fit = modeltoplot, par = "r", comp = 2, sel=sel)
TracePlot(fit = modeltoplot, par = "r", comp = 3, sel=sel)
TracePlot(fit = modeltoplot, par = "r", comp = 4, sel=sel)
par(mfrow=c(1,1))

#### create dataframes for ggplot (this takes a little while to run)
pred.resp.univar <- PredictorResponseUnivar(fit = modeltoplot, sel=sel, method="approx")
pred.resp.bivar  <- PredictorResponseBivar(fit = modeltoplot,  min.plot.dist = 1, sel=sel, method="approx")
pred.resp.bivar.levels <- PredictorResponseBivarLevels(pred.resp.df = pred.resp.bivar, Z = Z,
                                                          both_pairs = TRUE, qs = c(0.25, 0.5, 0.75))
risks.overall <- OverallRiskSummaries(fit = modeltoplot, qs = seq(0.25, 0.75, by = 0.05), q.fixed = 0.5, 
                                      method = "approx",sel=sel)
risks.singvar <- SingVarRiskSummaries(fit = modeltoplot, qs.diff = c(0.25, 0.75),
                                        q.fixed = c(0.25, 0.50, 0.75), method = "approx")
risks.int <- SingVarIntSummaries(fit = modeltoplot, qs.diff = c(0.25, 0.75), qs.fixed = c(0.25, 0.75))

save(pred.resp.univar, pred.resp.bivar, pred.resp.bivar.levels, risks.overall, risks.singvar, risks.int, 
     file=paste0("./saved_model/", modeltoplot.name,"_plots.RData"))

#load(paste0("Supervised/BKMR/saved_model/", modeltoplot.name,"_plots.RData"))

### run and save ggplots for each bkmr model
pdf(file=paste0("Supervised/BKMR/figures_pdf/univar_",plot.name,".pdf"), width=15, height=15)
ggplot(pred.resp.univar, aes(z, est, ymin = est - 1.96*se, ymax = est + 1.96*se)) + 
  geom_smooth(stat = "identity") + ylab("h(z)") + facet_wrap(~ variable) 
dev.off()

pdf(file=paste0("Supervised/BKMR/figures_pdf/bivar_",plot.name,".pdf"), width=30, height=30)
ggplot(pred.resp.bivar, aes(z1, z2, fill = est)) + 
  geom_raster() + 
  facet_grid(variable2 ~ variable1) +
  scale_fill_gradientn(colours=c("#0000FFFF","#FFFFFFFF","#FF0000FF")) +
  xlab("expos1") +
  ylab("expos2") +
  ggtitle("h(expos1, expos2)")
dev.off()

pdf(file=paste0("Supervised/BKMR/figures_pdf/bivar_levels_",plot.name,".pdf"), width=30, height=30)
ggplot(pred.resp.bivar.levels, aes(z1, est)) + 
  geom_smooth(aes(col = quantile), stat = "identity") + 
  facet_grid(variable2 ~ variable1) +
  ggtitle("h(expos1 | quantiles of expos2)") +
  xlab("expos1")
dev.off()

pdf(file=paste0("Supervised/BKMR/figures_pdf/overallrisks_",plot.name,".pdf"), width=10, height=10)
ggplot(risks.overall, aes(quantile, est, ymin = est - 1.96*sd, ymax = est + 1.96*sd)) +  
  geom_hline(yintercept=00, linetype="dashed", color="gray")+ 
  geom_pointrange() + scale_y_continuous(name="estimate") 
dev.off()

pdf(file=paste0("Supervised/BKMR/figures_pdf/singvar_",plot.name,".pdf"), width=5, height=10)
ggplot(risks.singvar, aes(variable, est, ymin = est - 1.96*sd,  ymax = est + 1.96*sd, col = q.fixed)) +  
  geom_hline(aes(yintercept=0), linetype="dashed", color="gray")+ 
  geom_pointrange(position = position_dodge(width = 0.75)) +  coord_flip() +  theme(legend.position="none") +
  scale_x_discrete(name="")+ scale_y_continuous(name="estimate") 
dev.off()

pdf(file=paste0("Supervised/BKMR/figures_pdf/", "interactplot_ex_",plot.name,".pdf"), width=5, height=10)
ggplot(risks.int, aes(variable, est, ymin = est - 1.96*sd, ymax = est + 1.96*sd)) + 
  geom_pointrange(position = position_dodge(width = 0.75)) + 
  geom_hline(yintercept = 0, lty = 2, col = "brown") + coord_flip()
dev.off()

